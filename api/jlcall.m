function varargout = jlcall(varargin)
%JLCALL Call Julia from Matlab.

    if nargin == 0
        varargout = {jlcall_test};
        return
    end

    opts = parse_inputs(varargin{:});

    % Save Julia input variables + settings to file
    [~, ~] = mkdir(opts.workspace); % ignore "folder exists" warning
    start_server(opts);
    call_server(opts);
    varargout = listen_for_output(opts);

end

function output = listen_for_output(opts)

    finished_file = fullfile(opts.workspace, 'jl_finished.txt');
    while ~exist(finished_file, 'file')
        pause(0.1);
    end
    delete(finished_file);
    output = load(fullfile(opts.workspace, 'jl_output.mat'));
    output = output.output;

end

function opts = jlcall_test

    opts = jlcall('x -> LinearAlgebra.norm(x)', ...
        {1:9}, {}, ...
        'project', '', ...
        'threads', 32, ...
        'modules', {'LinearAlgebra'}, ...
        'install', true, ...
        'workspace', relative_path('.jlcall'), ...
        'port', 2999, ...
        'restart', true ...
    );

end

function opts = parse_inputs(varargin)

    p = inputParser;
    addRequired(p, 'f', @ischar);
    addOptional(p, 'args', @iscell);
    addOptional(p, 'kwargs', {}, @iscell);
    addParameter(p, 'julia', 'julia', @ischar);
    addParameter(p, 'project', '', @ischar);
    addParameter(p, 'threads', maxNumCompThreads, @(x) validateattributes(x, {'numeric'}, {'scalar', 'integer', 'positive'}));
    addParameter(p, 'modules', {}, @iscell);
    addParameter(p, 'install', false, @(x) validateattributes(x, {'logical'}, {'scalar'}));
    addParameter(p, 'workspace', relative_path('.jlcall'), @ischar);
    addParameter(p, 'port', 3000, @(x) validateattributes(x, {'numeric'}, {'scalar', 'integer', 'positive'}));
    addParameter(p, 'restart', false, @(x) validateattributes(x, {'logical'}, {'scalar'}));
    parse(p, varargin{:});

    opts = p.Results;
    isevenlength = @(x) rem(numel(x), 2) == 0;
    isnamevaluepairs = @(x) isempty(x) || (isevenlength(x) && all(cellfun(@ischar, x(1:2:end))));
    if ~isnamevaluepairs(opts.kwargs)
        error('The value of ''kwargs'' is invalid. It must be a cell array of name-value pairs');
    end
    opts.args = reshape(opts.args, [], 1);
    opts.kwargs = reshape(opts.kwargs, [], 1);

end

function try_run(cmd)
    [st, ~] = system(cmd);
    fprintf('Command:\n\t%s\nStatus = %d\n', cmd, st);
    if st ~= 0
        error('Error running command:\n\t%s\n', cmd)
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

function st = call_server(opts)

    % Create temporary script for calling Julia server
    server_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.run("%s")', opts.workspace)
    });

    % Save inputs to disk
    save(fullfile(opts.workspace, 'jl_input.mat'), '-struct', 'opts', '-v7.3');

    % Create system command and call out to julia
    try_run([build_command(opts, 'client'), ' ', server_script]);

end

function init_workspace(opts)

    % Install JuliaFromMATLAB into workspace
    install_script = build_julia_script(opts, 'Pkg', {
        'println("* Installing JuliaFromMATLAB...")'
        'Pkg.develop(Pkg.PackageSpec(url = "https://github.com/jondeuce/JuliaFromMATLAB.jl"); io = devnull)'
        %TODO 'Pkg.add(Pkg.PackageSpec(url = "https://github.com/jondeuce/JuliaFromMATLAB.jl"); io = devnull)'
    });

    try_run([build_command(opts, 'client'), ' ', install_script]);

end

function init_server(opts)

    % Load JuliaFromMATLAB, installing it if not already installed in workspace
    %   see: https://discourse.julialang.org/t/how-to-use-pkg-dependencies-instead-of-pkg-installed/36416/15
    init_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.serve(%d)', opts.port)
    });

    try_run([build_command(opts, 'startup'), ' ', init_script, ' &']);

end

% Cleanup function for sending kill signal to Julia server
function kill_server(opts)

    fprintf('* Killing Julia server\n');
    kill_script = build_julia_script(opts, 'JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.kill(%d)', opts.port)
    });
    try_run([build_command(opts, 'client'), ' ', kill_script]);
    delete(fullfile(opts.workspace, 'tempfiles', '*'));
%     delete(fullfile(opts.workspace, '*.mat'));

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
            pause(1);
        end

        % Kill server on Matlab exit
        cleanup_server = onCleanup(@() kill_server(opts));
    end

end

function succ = ping_server(opts)

    % Create temporary file and try to delete file from julia server
    ping_file = jlcall_tempname(opts);
    fclose(fopen(ping_file, 'w'));

    ping_script = build_julia_script(opts, 'Sockets', {
        'try'
        sprintf('    Sockets.connect(%d)', opts.port)
        sprintf('    rm("%s"; force = true)', ping_file)
        'catch e'
        'end'
    });

    try_run([build_command(opts, 'client'), ' ', ping_script]);
    succ = ~exist(ping_file, 'file');

end

function jl_script = build_julia_script(opts, pkgs, body)

    if nargin < 2; body = {}; end
    if nargin < 1; pkgs = {}; end

    if ischar(pkgs); pkgs = {pkgs}; end
    if ischar(body); body = {body}; end

    % Create temporary helper Julia script
    jl_script = [jlcall_tempname(opts), '.jl'];
    fid = fopen(jl_script, 'w');
    cleanup_fid = onCleanup(@() fclose(fid));

    for ii = 1:length(pkgs)
        fprintf(fid, sprintf('import %s\n', pkgs{ii}));
    end
    for ii = 1:length(body)
        fprintf(fid, sprintf('%s\n', body{ii}));
    end

end

function tmp = jlcall_tempname(opts)

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
