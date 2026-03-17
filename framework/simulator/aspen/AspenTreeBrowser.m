classdef AspenTreeBrowser < handle
    % AspenTreeBrowser Aspen模型树浏览器
    %
    % 功能:
    %   - 连接Aspen模型并加载树结构
    %   - 搜索和过滤树节点
    %   - 获取节点值和单位
    %   - 导出变量映射配置
    %   - 支持复制路径到剪贴板
    %
    % 示例:
    %   browser = AspenTreeBrowser();
    %   browser.connect('C:/Models/process.bkp');
    %   nodes = browser.searchNodes('TEMP');
    %   value = browser.getNodeValue('\Data\Blocks\B1\Output\TEMP');

    properties (Access = private)
        aspenApp            % Aspen Plus应用对象
        modelFile           % 模型文件路径
        treeRoot            % 树根节点
        selectedNodes       % 已选中的节点
        nodeCache           % 缓存的节点信息
        searchResults       % 搜索结果
        isConnected         % 连接状态
    end

    methods
        function obj = AspenTreeBrowser()
            % AspenTreeBrowser 构造函数

            obj.aspenApp = [];
            obj.modelFile = '';
            obj.treeRoot = [];
            obj.selectedNodes = {};
            obj.nodeCache = containers.Map();
            obj.searchResults = {};
            obj.isConnected = false;
        end

        function connect(obj, modelPath)
            % connect 连接到Aspen模型
            %
            % 输入:
            %   modelPath - Aspen模型文件路径（.bkp文件）
            %
            % 例:
            %   browser.connect('C:/Models/process.bkp');

            if ~ispc
                error('AspenTreeBrowser:PlatformNotSupported', ...
                    'Aspen Plus COM仅支持Windows环境');
            end

            if ~isfile(modelPath)
                error('AspenTreeBrowser:FileNotFound', '模型文件不存在: %s', modelPath);
            end

            % Drop stale COM state before opening a new model.
            obj.disconnect();

            % Try common Aspen ProgIDs in priority order.
            progIds = {
                'Apwn.Document'
                'Apwn.Document.40.0'
                'Apwn.Document.39.0'
                'Apwn.Document.38.0'
                'Apwn.Document.37.0'
                'Apwn.Document.36.0'
                'Apwn.Document.35.0'
            };

            lastComError = [];
            for i = 1:length(progIds)
                try
                    obj.aspenApp = actxserver(progIds{i});
                    break;
                catch ME
                    lastComError = ME;
                    obj.aspenApp = [];
                end
            end

            if isempty(obj.aspenApp)
                if ~isempty(lastComError)
                    error('AspenTreeBrowser:AspenNotAvailable', ...
                        'Failed to create Aspen COM object. Tried ProgIDs: %s. Last error: %s', ...
                        strjoin(progIds, ', '), lastComError.message);
                end
                error('AspenTreeBrowser:AspenNotAvailable', ...
                    'Failed to create Aspen COM object (no detailed error returned).');
            end

            try
                % Use the same model-loading API as AspenPlusSimulator.
                obj.aspenApp.invoke('InitFromArchive2', modelPath);
            catch initError
                % Fallback for Aspen versions that prefer Open().
                try
                    obj.aspenApp.Open(modelPath, '', '', 0);
                catch openError
                    try
                        obj.aspenApp.Close(0);
                    catch
                    end
                    obj.aspenApp = [];
                    error('AspenTreeBrowser:ModelOpenFailed', ...
                        '加载Aspen模型失败。InitFromArchive2: %s | Open: %s', ...
                        initError.message, openError.message);
                end
            end

            obj.modelFile = modelPath;
            obj.isConnected = true;

            obj.loadTree();
        end

        function disconnect(obj)
            % disconnect 断开Aspen连接

            if ~isempty(obj.aspenApp)
                try
                    obj.aspenApp.Close(0);
                catch
                end
                obj.aspenApp = [];
            end

            obj.isConnected = false;
            obj.treeRoot = [];
            obj.nodeCache = containers.Map();
        end

        function results = searchNodes(obj, keyword, varargin)
            % searchNodes 搜索模型树中的节点
            %
            % 输入:
            %   keyword - 搜索关键词
            %   varargin - 可选参数
            %     'Type': 节点类型过滤（如'Block', 'Stream'）
            %     'MaxResults': 最大结果数，默认100
            %
            % 输出:
            %   results - 匹配的节点cell数组
            %
            % 例:
            %   nodes = browser.searchNodes('TEMP');
            %   nodes = browser.searchNodes('FEED', 'Type', 'Stream');

            if ~obj.isConnected
                error('AspenTreeBrowser:NotConnected', 'Aspen is not connected.');
            end

            % 解析参数
            p = inputParser;
            addParameter(p, 'Type', '', @ischar);
            addParameter(p, 'MaxResults', 100, @isnumeric);
            addParameter(p, 'CaseSensitive', false, @islogical);
            parse(p, varargin{:});

            nodeType = p.Results.Type;
            maxResults = p.Results.MaxResults;
            caseSensitive = p.Results.CaseSensitive;

            results = {};

            % 递归搜索
            obj.searchResults = {};
            obj.recursiveSearch(obj.treeRoot, keyword, nodeType, caseSensitive);

            % 截取最大结果数
            results = obj.searchResults(1:min(length(obj.searchResults), maxResults));
        end

        function value = getNodeValue(obj, nodePath)
            % getNodeValue 获取节点的当前值
            %
            % 输入:
            %   nodePath - 节点路径，例如'\Data\Blocks\B1\Output\TEMP'
            %
            % 输出:
            %   value - 节点值（数值或字符串）
            %
            % 例:
            %   temp = browser.getNodeValue('\Data\Blocks\B1\Output\TEMP');

            if ~obj.isConnected
                error('AspenTreeBrowser:NotConnected', 'Aspen is not connected.');
            end

            try
                node = obj.aspenApp.Tree.FindNode(nodePath);
                if ~isempty(node) && ~strcmp(class(node), 'handle')
                    value = node.Value;
                else
                    error('AspenTreeBrowser:NodeNotFound', '节点不存在: %s', nodePath);
                end
            catch ME
                error('AspenTreeBrowser:ValueRetrievalFailed', ...
                    '无法获取节点值 %s (错误: %s)', nodePath, ME.message);
            end
        end

        function unit = getNodeUnit(obj, nodePath)
            % getNodeUnit 获取节点的单位
            %
            % 输入:
            %   nodePath - 节点路径
            %
            % 输出:
            %   unit - 单位字符串，例如 'C' 或 'kmol/h'
            %
            % 例:
            %   unit = browser.getNodeUnit('\Data\Blocks\B1\Output\TEMP');

            if ~obj.isConnected
                error('AspenTreeBrowser:NotConnected', 'Aspen is not connected.');
            end

            try
                node = obj.aspenApp.Tree.FindNode(nodePath);
                if ~isempty(node) && ~strcmp(class(node), 'handle')
                    try
                        unit = node.UnitString;
                    catch
                        try
                            unit = node.Unit;
                        catch
                            unit = '';
                        end
                    end
                else
                    unit = '';
                end
            catch
                unit = '';
            end
        end

        function mapping = exportMapping(obj, selectedPaths)
            % exportMapping 导出选中节点的变量映射
            %
            % 输入:
            %   selectedPaths - 选中的节点路径cell数组
            %
            % 输出:
            %   mapping - struct，包含节点映射配置
            %
            % 例:
            %   mapping = browser.exportMapping({...
            %     '\Data\Blocks\B1\Input\TEMP', ...
            %     '\Data\Blocks\B1\Output\TEMP'
            %   });

            mapping = struct();
            mapping.variables = struct();
            mapping.results = struct();

            for i = 1:length(selectedPaths)
                path = selectedPaths{i};

                % 尝试获取值和单位
                try
                    value = obj.getNodeValue(path);
                    unit = obj.getNodeUnit(path);
                catch
                    value = [];
                    unit = '';
                end

                % 生成变量名（从路径推断）
                varName = obj.inferVariableNameFromPath(path);

                % 添加到映射
                entry = struct();
                entry.path = path;
                entry.value = value;
                entry.unit = unit;

                mapping.variables.(varName) = entry;
            end
        end

        function copyPathToClipboard(obj, nodePath)
            % copyPathToClipboard 将节点路径复制到剪贴板
            %
            % 输入:
            %   nodePath - 节点路径
            %
            % 例:
            %   browser.copyPathToClipboard('\Data\Blocks\B1\Output\TEMP');

            try
                clipboard('copy', nodePath);
            catch
                % 某些系统不支持clipboard
                warning('AspenTreeBrowser:ClipboardUnavailable', ...
                    '剪贴板操作不可用');
            end
        end

        function connected = isConnected_method(obj)
            % isConnected_method 检查连接状态

            connected = obj.isConnected;
        end

        function tree = getTreeStructure(obj)
            % getTreeStructure 获取完整的树结构
            %
            % 输出:
            %   tree - 树结构（nested struct）

            tree = obj.treeRoot;
        end

        function clearCache(obj)
            % clearCache 清除节点缓存

            obj.nodeCache = containers.Map();
        end
    end

    methods (Access = private)
        function loadTree(obj)
            % loadTree 从Aspen加载模型树
            try
                % 获取树根
                obj.treeRoot = struct();
                obj.treeRoot.name = 'Root';
                obj.treeRoot.path = '';
                obj.treeRoot.children = {};

                % Load \Data tree from Aspen COM
                dataNode = obj.loadTreeNodes('\Data', 'Data', 0);
                if isempty(dataNode)
                    % 回退到最小可用结构，避免UI空白
                    dataNode = struct();
                    dataNode.name = 'Data';
                    dataNode.path = '\Data';
                    dataNode.children = {};
                end

                if ~isfield(dataNode, 'children') || isempty(dataNode.children)
                    % Fallback top-level nodes when COM enumeration is unavailable.
                    fallbackChildren = {'Blocks', 'Streams', 'Properties', 'Flowsheeting Options', 'Calculator'};
                    dataNode.children = cell(1, numel(fallbackChildren));
                    for i = 1:numel(fallbackChildren)
                        child = struct();
                        child.name = fallbackChildren{i};
                        child.path = ['\Data\', fallbackChildren{i}];
                        child.children = {};
                        dataNode.children{i} = child;
                    end
                end


                obj.treeRoot.children = {dataNode};

            catch ME
                warning('AspenTreeBrowser:TreeLoadFailed', ...
                    '树加载失败: %s', ME.message);
            end
        end

        function nodeStruct = loadTreeNodes(obj, nodePath, nodeName, depth)
            % loadTreeNodes 递归加载Aspen树节点
            if nargin < 4
                depth = 0;
            end

            % Prevent very deep/large trees from freezing UI.
            maxDepth = 8;
            maxChildrenPerNode = 300;

            nodeStruct = struct();
            nodeStruct.name = nodeName;
            nodeStruct.path = nodePath;
            nodeStruct.children = {};

            if depth >= maxDepth
                return;
            end

            try
                parentNode = obj.aspenApp.Tree.FindNode(nodePath);
                if isempty(parentNode) || strcmp(class(parentNode), 'handle')
                    return;
                end
            catch
                return;
            end

            try
                childCount = parentNode.Elements.Count;
            catch
                childCount = 0;
            end

            if childCount <= 0
                return;
            end

            childCount = min(childCount, maxChildrenPerNode);
            for i = 1:childCount
                try
                    childObj = parentNode.Elements.Item(i - 1);
                    childName = char(string(childObj.Name));
                    childPath = [nodePath, '\', childName];

                    childNode = obj.loadTreeNodes(childPath, childName, depth + 1);
                    nodeStruct.children{end+1} = childNode; %#ok<AGROW>
                catch
                    % Ignore single-node failures and keep traversing siblings.
                end
            end
        end

        function recursiveSearch(obj, node, keyword, nodeType, caseSensitive)
            % recursiveSearch 递归搜索节点
            if isempty(node)
                return;
            end

            nodeName = node.name;
            if ~caseSensitive
                nodeName = lower(nodeName);
                keyword = lower(keyword);
            end

            if contains(nodeName, keyword)
                if isempty(nodeType) || ~isfield(node, 'type') || strcmp(node.type, nodeType)
                    obj.searchResults{end+1} = node;
                end
            end

            if isfield(node, 'children') && ~isempty(node.children)
                for i = 1:length(node.children)
                    obj.recursiveSearch(node.children{i}, keyword, nodeType, caseSensitive);
                end
            end
        end

        function varName = inferVariableNameFromPath(obj, nodePath)
            % inferVariableNameFromPath 从节点路径推断变量名

            % 简单的启发式方法：取路径的最后一个部分
            parts = split(nodePath, '\');
            varName = parts{end};

            % 移除特殊字符
            varName = regexprep(varName, '[^a-zA-Z0-9_]', '');
        end
    end
end
