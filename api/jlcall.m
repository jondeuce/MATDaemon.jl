function varargout = jlcall(varargin)
%JLCALL Call Julia from MATLAB.

    % Parse inputs
    [f_args, opts] = parse_inputs(varargin{:});

    % Initialize workspace for communicating between MATLAB and Julia
    init_workspace(opts);

    % Optionally start persistent Julia server
    if opts.server
        start_server(opts);
    end

    % Call Julia
    varargout = call_julia(f_args, opts);

end

function [f_args, opts] = parse_inputs(varargin)

    p = inputParser;

    % `maxNumCompThreads` had a deprecation warning in MATLAB R2015B,
    % but is no longer deprecated; silence the warning for old versions.
    warning('off', 'MATLAB:maxNumCompThreads:Deprecated')

    addOptional(p, 'f', '(args...; kwargs...) -> nothing', @ischar);
    addOptional(p, 'args', {}, @iscell);
    addOptional(p, 'kwargs', struct, @isstruct);
    addParameter(p, 'infile', [tempname, '.mat'], @ischar);
    addParameter(p, 'outfile', [tempname, '.mat'], @ischar);
    addParameter(p, 'runtime', try_find_julia_runtime, @ischar);
    addParameter(p, 'project', '', @ischar);
    addParameter(p, 'threads', maxNumCompThreads, @(x) validateattributes(x, {'numeric'}, {'scalar', 'integer', 'positive'}));
    addParameter(p, 'setup', '', @ischar);
    addParameter(p, 'modules', {}, @iscell);
    addParameter(p, 'cwd', pwd, @ischar);
    addParameter(p, 'workspace', relative_path('.jlcall'), @ischar);
    addParameter(p, 'server', true, @(x) validateattributes(x, {'logical'}, {'scalar'}));
    addParameter(p, 'port', 3000, @(x) validateattributes(x, {'numeric'}, {'scalar', 'integer', 'positive'}));
    addParameter(p, 'shared', true, @(x) validateattributes(x, {'logical'}, {'scalar'}));
    addParameter(p, 'restart', false, @(x) validateattributes(x, {'logical'}, {'scalar'}));
    addParameter(p, 'gc', true, @(x) validateattributes(x, {'logical'}, {'scalar'}));
    addParameter(p, 'debug', false, @(x) validateattributes(x, {'logical'}, {'scalar'}));

    parse(p, varargin{:});
    opts = p.Results;

    % Split Julia `f` args and kwargs out from options
    f_args(1).args = opts.args;
    f_args(1).kwargs = opts.kwargs;
    opts = rmfield(opts, {'args', 'kwargs'});

end

function init_workspace(opts)

    % Return if workspace is initialized
    if exist(opts.workspace, 'dir') && exist(fullfile(opts.workspace, 'Project.toml'), 'file')
        return
    end

    % Ignored outputs are needed to mute "folder exists" warning
    [~, ~] = mkdir(opts.workspace);

    % Install JuliaFromMATLAB into workspace
    install_script = build_julia_script(opts, 'Pkg', {
        'println("* Installing JuliaFromMATLAB...\n")'
        sprintf('Pkg.add(Pkg.PackageSpec(url = "https://github.com/jondeuce/JuliaFromMATLAB.jl", rev = "master"); io = %s)', jl_maybe_stdout(opts.debug))
    });

    try_run(opts, install_script, 'client', 'Running `JuliaFromMATLAB` install script');

end

function start_server(opts)

    mlock % Prevent MATLAB from clearing persistent variables via e.g. `clear all`
    persistent cleanup_server % Julia server cleanup object

    if opts.restart
        cleanup_server = []; % triggers server cleanup, if server has been started
    end
    is_server_off = isempty(cleanup_server);

    if is_server_off
        % Initialize Julia server
        if opts.debug
            fprintf('* Starting Julia server\n\n');
        end

        % If shared is false, each Julia server call is executed in it's own Module to avoid namespace collisions, etc.
        start_script = build_julia_script(opts, 'JuliaFromMATLAB', {
            sprintf('JuliaFromMATLAB.start(%d; shared = %s, verbose = %s)', opts.port, jl_bool(opts.shared), jl_bool(opts.debug))
        });

        try_run(opts, start_script, 'server', 'Running `JuliaFromMATLAB.start` script from Julia server');

        % Wait for server pong
        while ~ping_server(opts)
            pause(0.1);
        end

        % Kill server and collect garbage on MATLAB exit
        cleanup_server = onCleanup(@() kill_server(opts));
    end

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
        sprintf('JuliaFromMATLAB.kill(%d; verbose = %s)', opts.port, jl_bool(opts.debug))
    });

    try_run(opts, kill_script, 'client', 'Sending kill script to Julia server');

    if opts.gc
        collect_garbage(opts);
    end

end

function output = call_julia(f_args, opts)

    % Save `f` arguments to `opts.infile`
    save(opts.infile, '-struct', 'f_args', '-v7.3');

    % Save input parser results to .mat file in workspace folder
    save(fullfile(opts.workspace, 'jlcall_opts.mat'), '-struct', 'opts', '-v7.3');

    % Script to run from Julia
    job_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        'include(JuliaFromMATLAB.jlcall_script())'
    });

    if opts.server
        % Script to call the Julia server
        server_script = build_julia_script(opts, 'JuliaFromMATLAB', {
            sprintf('JuliaFromMATLAB.DaemonMode.runfile(raw"%s"; port = %d)', job_script, opts.port)
        });

        % Call out to Julia server
        try_run(opts, server_script, 'client', 'Sending `DaemonMode.runfile` script to Julia server');
    else
        % Call out to local Julia process
        try_run(opts, job_script, 'local', 'Calling `JuliaFromMATLAB.jlcall` from local Julia process');
    end

    % Load outputs from disk
    if exist(opts.outfile, 'file')
        output = load(opts.outfile);
        output = output.output;
    else
        % Throw error before garbage collecting below so that workspace folder can be inspected
        e.message = sprintf('Julia call failed to produce the expected output file:\n%s', opts.outfile);
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
    setenv('JULIAFROMMATLAB_WORKSPACE', opts.workspace);

    % Set Julia binary path and flags
    switch mode
        case 'server'
            flags = '--startup-file=no --optimize=3';
            detach = ' &';
        case 'client'
            flags = '--startup-file=no --optimize=0 --compile=min';
            detach = '';
        case 'local'
            flags = '--startup-file=no --optimize=3';
            detach = '';
        otherwise
            error('Unknown mode: ''%s''', mode)
    end

    % Build and run Julia command
    cmd = [opts.runtime, ' ', flags, ' ', script, detach];
    st = system(cmd);

    if opts.debug
        fprintf('* %s (status = %d):\n*   %s\n\n', msg, st, cmd);
    end

end

function runtime = try_find_julia_runtime()

    % Default value
    runtime = 'julia';

    try
        if isunix
            [st, res] = system('which julia');
        elseif ispc
            [st, res] = system('where julia');
        else
            return % default to 'julia'
        end
        if st == 0
            runtime = strtrim(res);
        end
    catch me
        % ignore error; default to 'julia'
    end

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

    tmp = fullfile(dirname, [pad_num(filecount), '_mat_', filename]);

end

function collect_garbage(opts)

    if exist(opts.infile, 'file'); delete(opts.infile); end
    if exist(opts.outfile, 'file'); delete(opts.outfile); end
    delete(fullfile(opts.workspace, 'tmp', '*'));
    delete(fullfile(opts.workspace, '*.mat'));

end

function path = relative_path(varargin)

    jlcall_dir = fileparts(mfilename('fullpath'));
    path = fullfile(jlcall_dir, varargin{:});

end

function str = jl_bool(bool)

    if bool
        str = 'true';
    else
        str = 'false';
    end

end

function str = jl_maybe_stdout(bool)

    if bool
        str = 'stdout';
    else
        str = 'devnull';
    end

end

function str = pad_num(s)

    if ~ischar(s)
        s = num2str(s);
    end

    str = [repmat('0', 1, max(4 - numel(s), 0)), s];

end
