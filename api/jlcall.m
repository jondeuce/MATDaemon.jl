function varargout = jlcall(varargin)
%JLCALL Call Julia from Matlab.

    % Save Julia input variables + settings to file
    opts = parse_inputs(varargin{:});
    start_server(opts);
    varargout = call_server(opts);

end

function opts = parse_inputs(varargin)

    p = inputParser;

    isevenlength = @(x) rem(numel(x), 2) == 0;
    isnamevaluepairs = @(x) iscell(x) && (isempty(x) || (isevenlength(x) && all(cellfun(@ischar, x(1:2:end)))));
    addRequired(p, 'f', @ischar);
    addOptional(p, 'args', @iscell);
    addOptional(p, 'kwargs', {}, @(x) isnamevaluepairs(x));
    addParameter(p, 'julia', 'julia', @ischar);
    addParameter(p, 'project', '', @ischar);
    addParameter(p, 'threads', maxNumCompThreads, @(x) validateattributes(x, {'numeric'}, {'scalar', 'integer', 'positive'}));
    addParameter(p, 'modules', {}, @iscell);
    addParameter(p, 'workspace', relative_path('.jlcall'), @ischar);
    addParameter(p, 'port', 3000, @(x) validateattributes(x, {'numeric'}, {'scalar', 'integer', 'positive'}));
    addParameter(p, 'restart', false, @(x) validateattributes(x, {'logical'}, {'scalar'}));
    addParameter(p, 'debug', false, @(x) validateattributes(x, {'logical'}, {'scalar'}));

    parse(p, varargin{:});
    opts = p.Results;

end

function start_server(opts)

    % mlock %TODO Prevent Matlab from clearing persistent variables via e.g. `clear all`
    persistent cleanup_server % Julia server cleanup object

    if opts.restart
        cleanup_server = []; % triggers server cleanup, if server has been started
        is_server_on = false;
    else
        is_server_on = ~isempty(cleanup_server);
    end

    if ~is_server_on
        % Create and run system command to start Julia server
        fprintf('* Starting Julia server\n');

        % Install JuliaFromMATLAB
        if ~exist(fullfile(opts.workspace, 'Project.toml'), 'file')
            init_workspace(opts);
        end

        % Initialize Julia server
        init_server(opts);

        % Wait for server ping
        while ~ping_server(opts)
            pause(0.1);
        end

        % Kill server on Matlab exit
        cleanup_server = onCleanup(@() kill_server(opts));
    end

end

function init_workspace(opts)

    [~, ~] = mkdir(opts.workspace); % ignore "folder exists" warning

    % Install JuliaFromMATLAB into workspace
    install_script = build_julia_script(opts, 'Pkg', {
        'println("* Installing JuliaFromMATLAB...")'
        'Pkg.develop(Pkg.PackageSpec(url = "https://github.com/jondeuce/JuliaFromMATLAB.jl"); io = devnull)'
        %TODO 'Pkg.add(Pkg.PackageSpec(url = "https://github.com/jondeuce/JuliaFromMATLAB.jl"); io = devnull)'
    });

    try_run(opts, [build_command(opts, 'client'), ' ', install_script]);

end

function init_server(opts)

    % Load JuliaFromMATLAB, installing it if not already installed in workspace
    %   see: https://discourse.julialang.org/t/how-to-use-pkg-dependencies-instead-of-pkg-installed/36416/15
    init_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.serve(%d)', opts.port)
    });

    try_run(opts, [build_command(opts, 'startup'), ' ', init_script, ' &']);

end

function succ = ping_server(opts)

    try
        tcpclient('127.0.0.1', opts.port);
        succ = true;
    catch me
        if strcmp(me.identifier, 'MATLAB:networklib:tcpclient:cannotCreateObject')
            succ = false;
        else
            rethrow(me)
        end
    end

end

function kill_server(opts)

    fprintf('* Killing Julia server\n');
    kill_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.kill(%d)', opts.port)
    });
    try_run(opts, [build_command(opts, 'client'), ' ', kill_script]);
    delete(fullfile(opts.workspace, 'tempfiles', '*'));
    delete(fullfile(opts.workspace, '*.mat'));

end

function output = call_server(opts)

    % Script to run from the Julia server
    job_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.run("%s")', opts.workspace)
    });

    % Script to call the Julia server
    server_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.DaemonMode.runfile("%s"; port = %d)', job_script, opts.port)
    });

    % Save inputs to disk
    save(fullfile(opts.workspace, 'jl_input.mat'), '-struct', 'opts', '-v7.3');

    % Create system command and call out to julia
    try_run(opts, [build_command(opts, 'client'), ' ', server_script]);

    % Load outputs from disk
    output = load(fullfile(opts.workspace, 'jl_output.mat'));
    output = {output.output{:}};

end

function jl_script = build_julia_script(opts, pkgs, body)

    if nargin < 2; body = {}; end
    if nargin < 1; pkgs = {}; end

    if ischar(pkgs); pkgs = {pkgs}; end
    if ischar(body); body = {body}; end

    % Create temporary helper Julia script
    jl_script = [workspace_tempname(opts), '.jl'];
    fid = fopen(jl_script, 'w');
    cleanup_fid = onCleanup(@() fclose(fid));

    for ii = 1:length(pkgs)
        fprintf(fid, sprintf('import %s\n', pkgs{ii}));
    end
    for ii = 1:length(body)
        fprintf(fid, sprintf('%s\n', body{ii}));
    end

end

function cmd = build_command(opts, mode)

    % Set Julia binary path and flags
    switch mode
        case 'startup'
            flags = sprintf('--startup-file=no --project=%s --optimize=3 --threads=%d', opts.workspace, opts.threads);
        case 'client'
            flags = sprintf('--quiet --startup-file=no --compile=min --project=%s', opts.workspace);
        otherwise
            error('Unknown mode: ''%s''', mode)
    end

    cmd = [opts.julia, ' ', flags];

end

function try_run(opts, cmd)
    st = system(cmd);
    if opts.debug
        fprintf('* Command (status = %d):\n\t%s\n', st, cmd);
    end
end

function tmp = workspace_tempname(opts)

    tempfiles_dir = fullfile(opts.workspace, 'tempfiles');
    [~, ~] = mkdir(tempfiles_dir); % ignore "folder exists" warning
    [dirname, filename] = fileparts(tempname(tempfiles_dir));

    persistent filecount
    if isempty(filecount)
        filecount = 0;
    else
        filecount = filecount + 1;
    end
    prefix = pad(num2str(filecount), 4, 'left', '0');
    tmp = fullfile(dirname, [prefix, '_mat_', filename]);

end

function path = relative_path(varargin)

    jlcall_dir = fileparts(mfilename('fullpath'));
    path = fullfile(jlcall_dir, varargin{:});

end
