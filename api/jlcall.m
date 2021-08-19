function varargout = jlcall(varargin)
%JLCALL Call Julia from MATLAB.

    % Save Julia input variables + settings to file
    opts = parse_inputs(varargin{:});
    start_server(opts);
    varargout = call_server(opts);

end

function opts = parse_inputs(varargin)

    p = inputParser;

    addOptional(p, 'f', '(args...; kwargs...) -> nothing', @ischar);
    addOptional(p, 'args', {}, @iscell);
    addOptional(p, 'kwargs', struct, @isstruct);
    addParameter(p, 'julia', 'julia', @ischar);
    addParameter(p, 'project', '', @ischar);
    addParameter(p, 'threads', maxNumCompThreads, @(x) validateattributes(x, {'numeric'}, {'scalar', 'integer', 'positive'}));
    addParameter(p, 'setup', '', @ischar);
    addParameter(p, 'modules', {}, @iscell);
    addParameter(p, 'workspace', relative_path('.jlcall'), @ischar);
    addParameter(p, 'shared', true, @(x) validateattributes(x, {'logical'}, {'scalar'}));
    addParameter(p, 'port', 1337, @(x) validateattributes(x, {'numeric'}, {'scalar', 'integer', 'positive'}));
    addParameter(p, 'restart', false, @(x) validateattributes(x, {'logical'}, {'scalar'}));
    addParameter(p, 'gc', true, @(x) validateattributes(x, {'logical'}, {'scalar'}));
    addParameter(p, 'debug', false, @(x) validateattributes(x, {'logical'}, {'scalar'}));

    parse(p, varargin{:});
    opts = p.Results;

end

function start_server(opts)

    mlock % Prevent MATLAB from clearing persistent variables via e.g. `clear all`
    persistent cleanup_server % Julia server cleanup object

    if opts.restart
        cleanup_server = []; % triggers server cleanup, if server has been started
        is_server_on = false;
    else
        is_server_on = ~isempty(cleanup_server);
    end

    if ~is_server_on
        if opts.debug
            fprintf('* Starting Julia server\n\n');
        end

        % Install JuliaFromMATLAB if necessary
        if ~exist(fullfile(opts.workspace, 'Project.toml'), 'file')
            init_workspace(opts);
        end

        % Initialize Julia server
        init_server(opts);

        % Wait for server pong
        while ~ping_server(opts)
            pause(0.1);
        end

        % Kill server and collect garbage on MATLAB exit
        cleanup_server = onCleanup(@() kill_server(opts));
    end

end

function init_workspace(opts)

    [~, ~] = mkdir(opts.workspace); % ignore "folder exists" warning

    % Install JuliaFromMATLAB into workspace
    install_script = build_julia_script(opts, 'Pkg', {
        'println("* Installing JuliaFromMATLAB...\n")'
        sprintf('Pkg.add(Pkg.PackageSpec(url = "https://github.com/jondeuce/JuliaFromMATLAB.jl", rev = "master"); io = %s)', maybe_stdout(opts.debug))
    });

    try_run(opts, install_script, 'client', 'Sending `JuliaFromMATLAB` install script to Julia server');

end

function init_server(opts)

    % If shared is false, each Julia server call is executed in it's own Module to avoid namespace collisions, etc.
    init_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.start(%d; shared = %s, verbose = %s)', opts.port, bool_string(opts.shared), bool_string(opts.debug))
    });

    try_run(opts, init_script, 'server', 'Running `JuliaFromMATLAB.start` script from Julia server');

end

function succ = ping_server(opts)

    try
        tcpclient('127.0.0.1', opts.port);
        succ = true;
    catch me
        if strcmpi(me.identifier, 'MATLAB:networklib:tcpclient:cannotCreateObject')
            succ = false;
        else
            rethrow(me)
        end
    end

end

function kill_server(opts)

    if opts.debug
        fprintf('* Killing Julia server\n\n');
    end

    kill_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.kill(%d; verbose = %s)', opts.port, bool_string(opts.debug))
    });

    try_run(opts, kill_script, 'client', 'Sending kill script to Julia server');

    if opts.gc
        collect_garbage(opts);
    end

end

function output = call_server(opts)

    % Script to run from the Julia server
    job_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.jlcall(@__MODULE__; workspace = "%s")', opts.workspace)
    });

    % Script to call the Julia server
    server_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.DaemonMode.runfile("%s"; port = %d, output = %s)', job_script, opts.port, maybe_stdout(opts.debug))
    });

    % Save inputs to disk
    save(fullfile(opts.workspace, 'jl_input.mat'), '-struct', 'opts', '-v7.3');

    % Call out to Julia server
    try_run(opts, server_script, 'client', 'Sending `DaemonMode.runfile` script to Julia server');

    % Load outputs from disk
    output_file = fullfile(opts.workspace, 'jl_output.mat');
    if exist(output_file, 'file')
        output = load(output_file);
        output = output.output;
    else
        % Throw error before garbage collecting below so that workspace folder can be inspected
        e.message = sprintf('Julia call failed to produce the expected output file:\n%s', output_file);
        e.identifier = 'jlcall:fileNotFound';
        error(e)
    end

    % Collect temporary garbage
    if opts.gc
        collect_garbage(opts);
    end

end

function jl_script = build_julia_script(opts, pkgs, body)

    if nargin < 2; body = {}; end
    if nargin < 1; pkgs = {}; end

    if ischar(pkgs); pkgs = {pkgs}; end
    if ischar(body); body = {body}; end

    % Create temporary Julia script
    jl_script = [workspace_tempname(opts), '.jl'];
    fid = fopen(jl_script, 'w');
    cleanup_fid = onCleanup(@() fclose(fid));

    for ii = 1:length(pkgs)
        fprintf(fid, 'import %s\n', pkgs{ii});
    end
    for ii = 1:length(body)
        fprintf(fid, '%s\n', body{ii});
    end

end

function try_run(opts, script, mode, msg)

    if nargin < 4
        msg = 'Command';
    end

    % Set Julia environment variables
    setenv('JULIA_NUM_THREADS', num2str(opts.threads));
    setenv('JULIA_PROJECT', opts.workspace);

    % Set Julia binary path and flags
    switch mode
        case 'server'
            flags = '--startup-file=no --optimize=3';
            detach = ' &';
        case 'client'
            flags = '--startup-file=no --optimize=0 --compile=min';
            detach = '';
        otherwise
            error('Unknown mode: ''%s''', mode)
    end

    % Build and run Julia command
    cmd = [opts.julia, ' ', flags, ' ', script, detach];
    st = system(cmd);

    if opts.debug
        fprintf('* %s (status = %d):\n*   %s\n\n', msg, st, cmd);
    end

end

function collect_garbage(opts)

    % Recursively delete workspace folder and contents
    delete(fullfile(opts.workspace, 'tmp', '*'));
    delete(fullfile(opts.workspace, '*.mat'));

end

function tmp = workspace_tempname(opts)

    tmp_dir = fullfile(opts.workspace, 'tmp');
    [~, ~] = mkdir(tmp_dir); % ignore "folder exists" warning
    [dirname, filename] = fileparts(tempname(tmp_dir));

    persistent filecount
    if isempty(filecount)
        filecount = 0;
    else
        filecount = mod(filecount + 1, 10000);
    end

    prefix = pad(num2str(filecount), 4, 'left', '0');
    tmp = fullfile(dirname, [prefix, '_mat_', filename]);

end

function str = bool_string(bool)

    if bool
        str = 'true';
    else
        str = 'false';
    end

end

function str = maybe_stdout(bool)

    if bool
        str = 'stdout';
    else
        str = 'devnull';
    end

end

function path = relative_path(varargin)

    jlcall_dir = fileparts(mfilename('fullpath'));
    path = fullfile(jlcall_dir, varargin{:});

end
