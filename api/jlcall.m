function varargout = jlcall(varargin)
%JLCALL Call Julia from Matlab.

    if nargin == 0
        varargout = {jlcall_test};
        return
    end

    opts = parse_inputs(varargin{:});

    % Save Julia input variables + settings to file
    [~, ~] = mkdir(opts.workspace); % ignore "folder exists" warning
    save(fullfile(opts.workspace, 'jl_input.mat'), '-struct', 'opts', '-v7.3');
    start_server(opts);
    call_server(opts);

    varargout = {opts};

end

function opts = jlcall_test

    opts = jlcall('Base.BroadcastFunction(sqrt)', ...
        {1:9}, {}, ...
        'project', relative_path('myproject'), ...
        'threads', 32, ...
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
    addParameter(p, 'workspace', relative_path('.jlcall'), @ischar);
    addParameter(p, 'restart', false,  @(x) validateattributes(x, {'logical'}, {'scalar'}));
    addParameter(p, 'port', 3000, @(x) validateattributes(x, {'numeric'}, {'scalar', 'integer', 'positive'}));
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
    server_script = build_julia_script('JuliaFromMATLAB', {
        sprintf('JuliaFromMATLAB.run("%s")', opts.workspace)
    });
    cleanup_server_script = onCleanup(@() delete([server_script, '*']));

    % Create system command
    cmd = [build_command(opts, 'client'), ' ', server_script];

    % Call out to julia
    [st, ~] = system(cmd, '-echo');

end

function jl_script = make_server_start_script(opts)
    jl_script = build_julia_script('Pkg', {
        'try'
        '    import JuliaFromMATLAB'
        'catch e1'
        '    @info "Installing JuliaFromMATLAB..."'
        'Pkg.develop(Pkg.PackageSpec(url = "https://github.com/jondeuce/JuliaFromMATLAB.jl"); io = devnull)'
        %TODO '    Pkg.add(Pkg.PackageSpec(url = "https://github.com/jondeuce/JuliaFromMATLAB.jl"); io = devnull)'
        '    try'
        '        import JuliaFromMATLAB'
        '        @info "...done"'
        '    catch e2'
        '        @warn "Error initializing JuliaFromMATLAB" exception=(e2, catch_backtrace())'
        '    end'
        'end'
        ''
        sprintf('JuliaFromMATLAB.serve(%d)', opts.port)
    });
end

% Cleanup function for sending kill signal to Julia server
function kill_server(opts)
    fprintf('* Killing Julia server\n');
    kill_script = build_julia_script('JuliaFromMATLAB', sprintf('JuliaFromMATLAB.kill(%d)', opts.port));
    cleanup_kill_script = onCleanup(@() delete([kill_script, '*']));
    cmd = [build_command(opts, 'client'), ' ', kill_script];
    [st, ~] = system(cmd, '-echo');
end

function start_server(opts)

    % mlock %TODO Prevent Matlab from clearing persistent variables via e.g. `clear all`
    persistent cleanup_server % Julia server cleanup object

    if opts.restart
        cleanup_server = []; % triggers server cleanup, if server has been started
        start_server = true;
    else
        start_server = isempty(cleanup_server);
    end

    if start_server
        % Create and run system command to start Julia server
        fprintf('* Starting Julia server\n');

        server_script = make_server_start_script(opts);
        cleanup_server_script = onCleanup(@() delete([server_script, '*']));
        cmd = [build_command(opts, 'startup'), ' ', server_script, ' &'];
        [st, ~] = system(cmd, '-echo');

        % Wait for server ping
        while ~ping_server(opts)
            pause(1)
        end

        % Kill server on Matlab exit
        cleanup_server = onCleanup(@() kill_server(opts));
    end

end

function succ = ping_server(opts)

    % Create temporary file and try to delete file from julia server
    ping_file = tempname;
    fclose(fopen(ping_file, 'w'));
    cleanup_ping_file = onCleanup(@() delete([ping_file, '*']));

    ping_script = build_julia_script('Sockets', {
        'try'
        sprintf('    Sockets.connect(%d)', opts.port)
        sprintf('    rm("%s"; force = true)', ping_file)
        'catch e'
        'end'
    });
    cleanup_ping_script = onCleanup(@() delete([ping_script, '*']));

    cmd = [build_command(opts, 'client'), ' ', ping_script];
    [st, ~] = system(cmd, '-echo');
    succ = ~exist(ping_file, 'file');

end

function jl_script = build_julia_script(pkgs, body)

    if nargin < 2; body = {}; end
    if nargin < 1; pkgs = {}; end

    if ischar(pkgs); pkgs = {pkgs}; end
    if ischar(body); body = {body}; end

    % Create temporary helper Julia script
    jl_script = [tempname, '.jl'];
    fid = fopen(jl_script, 'w');
    cleanup_fid = onCleanup(@() fclose(fid));

    for ii = 1:length(pkgs)
        fprintf(fid, sprintf('import %s\n', pkgs{ii}));
    end
    for ii = 1:length(body)
        fprintf(fid, sprintf('%s\n', body{ii}));
    end

end

function path = relative_path(varargin)

    jlcall_dir = fileparts(mfilename('fullpath'));
    path = fullfile(jlcall_dir, varargin{:});

end
