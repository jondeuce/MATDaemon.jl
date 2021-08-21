function varargout = jlcall(varargin)
%JLCALL Call Julia from MATLAB.

    % Parse inputs
    opts = parse_inputs(varargin{:});

    % Initialize workspace for communicating between MATLAB and Julia
    init_workspace(opts);

    % Optionally start persistent Julia server
    if opts.server
        start_server(opts);
    end

    % Call Julia
    varargout = call_julia(opts);

end

function opts = parse_inputs(varargin)

    p = inputParser;

    addOptional(p, 'f', '(args...; kwargs...) -> nothing', @ischar);
    addOptional(p, 'args', {}, @iscell);
    addOptional(p, 'kwargs', struct, @isstruct);
    addParameter(p, 'julia', try_find_julia, @ischar);
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

function init_server(opts)

    % If shared is false, each Julia server call is executed in it's own Module to avoid namespace collisions, etc.
    init_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.start(%d; shared = %s, verbose = %s)', opts.port, jl_bool(opts.shared), jl_bool(opts.debug))
    });

    try_run(opts, init_script, 'server', 'Running `JuliaFromMATLAB.start` script from Julia server');

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
        init_server(opts);

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

function output = call_julia(opts)

    % Save MATLAB inputs to .mat file in workspace folder
    save(fullfile(opts.workspace, 'jl_input.mat'), '-struct', 'opts', '-v7.3');

    % Script to run from Julia
    job_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.@jlcall(%s)', jl_opts_without_args_kwargs(opts))
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
        case 'local'
            flags = '--startup-file=no --optimize=3';
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

function julia = try_find_julia()

    % Default value
    julia = 'julia';

    try
        if isunix
            [st, res] = system('which julia');
        elseif ispc
            [st, res] = system('where julia');
        else
            % Default to 'julia'
            return
        end
        if st == 0
            julia = strtrim(res);
        end
    catch me
        % Ignore error; default to 'julia'
    end

end

function jl_opts = jl_opts_without_args_kwargs(opts)

    % This is a bit of a hack, but it is a nice way to easily pass the user settings to Julia without
    % incurring the full cost of loading the args and/or kwargs, which may have large memory footprints
    jl_opts = {
        sprintf('f         = raw"%s",', opts.f)
        sprintf('julia     = raw"%s",', opts.julia)
        sprintf('project   = raw"%s",', opts.project)
        sprintf('threads   = %d,',      opts.threads)
        sprintf('setup     = raw"%s",', opts.setup)
        sprintf('modules   = %s,',      jl_vector_of_strings(opts.modules))
        sprintf('cwd       = raw"%s",', opts.cwd)
        sprintf('workspace = raw"%s",', opts.workspace)
        sprintf('server    = %s,',      jl_bool(opts.server))
        sprintf('port      = %d,',      opts.port)
        sprintf('shared    = %s,',      jl_bool(opts.shared))
        sprintf('restart   = %s,',      jl_bool(opts.restart))
        sprintf('gc        = %s,',      jl_bool(opts.gc))
        sprintf('debug     = %s,',      jl_bool(opts.debug))
    };
    jl_opts = ['JuliaFromMATLAB.JLCallOptions(;', sprintf('\n    %s', jl_opts{:}), sprintf('\n)')];

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

function collect_garbage(opts)

    % Recursively delete workspace folder and contents
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

function str = jl_vector_of_strings(cell_strs)

    if isempty(cell_strs)
        str = 'Any[]';
    else
        str = ['Any[', sprintf('raw"%s",', cell_strs{:}), ']'];
    end

end
