classdef AspenTreeBrowserGUI < handle
    % AspenTreeBrowserGUI Aspen模型树浏览器GUI
    % 通过COM接口遍历Aspen树，提供交互式选择界面
    %
    % 功能:
    %   - 自动遍历Aspen树结构
    %   - 提供树形UI选择
    %   - 自动生成nodeMapping
    %   - 支持节点搜索和过滤
    %   - 右键菜单标记输入变量/输出结果
    %
    % 示例:
    %   browser = AspenTreeBrowserGUI();
    %   browser.connectModel('model.bkp');
    %   browser.buildTreeUI(parentFigure);
    %   [varMap, resMap] = browser.getSelectedMappings();

    properties (Access = public)
        treeView;              % UI树控件 (uitree)
        selectedVariables;     % 用户选中的输入变量 struct array
        selectedResults;       % 用户选中的输出结果 struct array
    end

    properties (Access = private)
        logger;                % Logger实例
        backend;               % AspenTreeBrowser后端实例
        aspenFilePath;         % Aspen文件路径
        nodePathMap;           % containers.Map: UI节点 -> Aspen路径
        selectionMode;         % 当前选择模式 ('variable'/'result'/'none')
        isModelConnected;      % 模型连接状态
    end

    methods
        function obj = AspenTreeBrowserGUI()
            % AspenTreeBrowserGUI 构造函数
            %
            % 输出: obj - AspenTreeBrowserGUI对象

            if exist('Logger', 'class')
                obj.logger = Logger.getLogger('AspenTreeBrowserGUI');
            else
                obj.logger = [];
            end

            obj.backend = [];
            obj.aspenFilePath = '';
            obj.selectedVariables = struct([]);
            obj.selectedResults = struct([]);
            obj.nodePathMap = containers.Map();
            obj.selectionMode = 'none';
            obj.isModelConnected = false;
            obj.treeView = [];
        end

        function success = connectModel(obj, modelPath)
            % connectModel 连接到Aspen模型
            %
            % 输入:
            %   modelPath - Aspen模型文件路径 (.bkp)
            %
            % 输出:
            %   success - 是否连接成功

            success = false;

            if ~isfile(modelPath)
                obj.logMsg('error', sprintf('模型文件不存在: %s', modelPath));
                return;
            end

            try
                obj.backend = AspenTreeBrowser();
                obj.backend.connect(modelPath);
                obj.aspenFilePath = modelPath;
                obj.isModelConnected = true;
                success = true;
                obj.logMsg('info', sprintf('已连接Aspen模型: %s', modelPath));
            catch ME
                obj.logMsg('error', sprintf('连接失败: %s', ME.message));
                obj.isModelConnected = false;
            end
        end

        function disconnect(obj)
            % disconnect 断开Aspen连接

            if ~isempty(obj.backend)
                obj.backend.disconnect();
            end
            obj.isModelConnected = false;
            obj.logMsg('info', '已断开Aspen连接');
        end

        function buildTreeUI(obj, parentContainer, varargin)
            % buildTreeUI 构建UI树控件，显示Aspen树
            %
            % 输入:
            %   parentContainer - 父UI容器 (figure/panel/tab)
            %   varargin - 可选参数:
            %       'Position', [x,y,w,h] - 树控件位置
            %       'SelectionMode', 'variable'/'result'/'none'

            p = inputParser();
            p.addParameter('Position', [10, 10, 400, 500]);
            p.addParameter('SelectionMode', 'none');
            p.parse(varargin{:});

            obj.selectionMode = p.Results.SelectionMode;

            % 创建树控件
            obj.treeView = uitree(parentContainer);
            obj.treeView.Position = p.Results.Position;

            % 添加右键菜单
            obj.treeView.ContextMenu = obj.createContextMenu(parentContainer);

            % 加载树结构
            if obj.isModelConnected
                obj.loadTreeFromBackend();
            else
                uitreenode(obj.treeView, 'Text', '(未连接Aspen模型)');
            end
        end

        function refreshTree(obj)
            % refreshTree 刷新树结构
            if isempty(obj.treeView)
                return;
            end

            % 清除现有节点
            delete(obj.treeView.Children);
            obj.nodePathMap = containers.Map();

            if obj.isModelConnected
                obj.loadTreeFromBackend();
            end
        end

        function [varMap, resMap] = getSelectedMappings(obj)
            % getSelectedMappings 获取用户选中的变量和结果映射
            %
            % 输出:
            %   varMap - struct，键为变量名，值为Aspen路径
            %   resMap - struct，键为结果名，值为Aspen路径

            varMap = struct();
            for i = 1:length(obj.selectedVariables)
                v = obj.selectedVariables(i);
                varMap.(v.name) = v.aspenPath;
            end

            resMap = struct();
            for i = 1:length(obj.selectedResults)
                r = obj.selectedResults(i);
                resMap.(r.name) = r.aspenPath;
            end
        end

        function nodeMapping = generateNodeMapping(obj)
            % generateNodeMapping 生成完整的nodeMapping配置
            %
            % 输出:
            %   nodeMapping - struct，包含variables和results映射

            [varMap, resMap] = obj.getSelectedMappings();
            nodeMapping = struct();
            nodeMapping.variables = varMap;
            nodeMapping.results = resMap;
        end

        function connected = isConnected(obj)
            % isConnected 检查连接状态

            connected = obj.isModelConnected;
        end

        function clearSelections(obj)
            % clearSelections 清除所有选择

            obj.selectedVariables = struct([]);
            obj.selectedResults = struct([]);
            obj.refreshTree();
        end
    end

    methods (Access = private)
        function loadTreeFromBackend(obj)
            % loadTreeFromBackend 从后端加载树结构到UI

            try
                treeStruct = obj.backend.getTreeStructure();
                addedAnyNode = false;
                if ~isempty(treeStruct) && isfield(treeStruct, 'children')
                    for i = 1:length(treeStruct.children)
                        obj.addTreeNodeRecursive(treeStruct.children{i}, obj.treeView);
                        addedAnyNode = true;
                    end
                end
                if ~addedAnyNode
                    uitreenode(obj.treeView, 'Text', '(未发现可展示节点)');
                end
                obj.logMsg('info', 'Aspen树已加载到UI');
            catch ME
                obj.logMsg('warning', sprintf('树加载失败: %s', ME.message));
                uitreenode(obj.treeView, 'Text', '(树加载失败)');
            end
        end

        function addTreeNodeRecursive(obj, nodeStruct, uiParent)
            % addTreeNodeRecursive 递归添加树节点

            if isempty(nodeStruct)
                return;
            end

            nodeName = nodeStruct.name;
            nodePath = '';
            if isfield(nodeStruct, 'path')
                nodePath = nodeStruct.path;
            end

            % 创建UI节点
            uiNode = uitreenode(uiParent, 'Text', nodeName);

            % 存储路径映射
            if ~isempty(nodePath)
                key = sprintf('node_%d', obj.nodePathMap.Count + 1);
                obj.nodePathMap(key) = nodePath;
                uiNode.NodeData = struct('path', nodePath, 'mapKey', key);
            end

            % 递归添加子节点
            if isfield(nodeStruct, 'children') && ~isempty(nodeStruct.children)
                for i = 1:length(nodeStruct.children)
                    obj.addTreeNodeRecursive(nodeStruct.children{i}, uiNode);
                end
            end
        end

        function contextMenu = createContextMenu(obj, parentFigure)
            % createContextMenu 创建右键菜单

            contextMenu = uicontextmenu(parentFigure);

            uimenu(contextMenu, 'Text', '标记为输入变量', ...
                'MenuSelectedFcn', @(~, ~) obj.markAsVariable());

            uimenu(contextMenu, 'Text', '标记为输出结果', ...
                'MenuSelectedFcn', @(~, ~) obj.markAsResult());

            uimenu(contextMenu, 'Text', '取消标记', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) obj.unmarkNode());

            uimenu(contextMenu, 'Text', '复制节点路径', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) obj.copyNodePath());
        end

        function markAsVariable(obj)
            % markAsVariable 标记选中节点为输入变量

            selectedNode = obj.treeView.SelectedNodes;
            if isempty(selectedNode)
                return;
            end

            node = selectedNode(1);
            if isempty(node.NodeData) || ~isfield(node.NodeData, 'path')
                return;
            end

            nodeName = node.Text;
            aspenPath = node.NodeData.path;

            % 提示用户输入变量名
            varName = inputdlg('变量名:', '标记为输入变量', [1, 30], {nodeName});
            if isempty(varName)
                return;
            end

            newVar = struct('name', varName{1}, 'aspenPath', aspenPath);

            if isempty(obj.selectedVariables)
                obj.selectedVariables = newVar;
            else
                obj.selectedVariables(end+1) = newVar;
            end

            node.Text = sprintf('%s [输入: %s]', nodeName, varName{1});
            obj.logMsg('info', sprintf('标记输入变量: %s -> %s', varName{1}, aspenPath));
        end

        function markAsResult(obj)
            % markAsResult 标记选中节点为输出结果

            selectedNode = obj.treeView.SelectedNodes;
            if isempty(selectedNode)
                return;
            end

            node = selectedNode(1);
            if isempty(node.NodeData) || ~isfield(node.NodeData, 'path')
                return;
            end

            nodeName = node.Text;
            aspenPath = node.NodeData.path;

            resName = inputdlg('结果名:', '标记为输出结果', [1, 30], {nodeName});
            if isempty(resName)
                return;
            end

            newRes = struct('name', resName{1}, 'aspenPath', aspenPath);

            if isempty(obj.selectedResults)
                obj.selectedResults = newRes;
            else
                obj.selectedResults(end+1) = newRes;
            end

            node.Text = sprintf('%s [输出: %s]', nodeName, resName{1});
            obj.logMsg('info', sprintf('标记输出结果: %s -> %s', resName{1}, aspenPath));
        end

        function unmarkNode(obj)
            % unmarkNode 取消标记选中节点

            selectedNode = obj.treeView.SelectedNodes;
            if isempty(selectedNode)
                return;
            end

            node = selectedNode(1);
            if isempty(node.NodeData) || ~isfield(node.NodeData, 'path')
                return;
            end

            aspenPath = node.NodeData.path;

            % 从变量列表中移除
            if ~isempty(obj.selectedVariables)
                paths = {obj.selectedVariables.aspenPath};
                idx = strcmp(paths, aspenPath);
                if any(idx)
                    obj.selectedVariables(idx) = [];
                end
            end

            % 从结果列表中移除
            if ~isempty(obj.selectedResults)
                paths = {obj.selectedResults.aspenPath};
                idx = strcmp(paths, aspenPath);
                if any(idx)
                    obj.selectedResults(idx) = [];
                end
            end

            % 恢复节点文本 (移除标记)
            text = node.Text;
            bracketIdx = strfind(text, ' [');
            if ~isempty(bracketIdx)
                node.Text = text(1:bracketIdx(1)-1);
            end

            obj.logMsg('info', sprintf('取消标记: %s', aspenPath));
        end

        function copyNodePath(obj)
            % copyNodePath 复制选中节点的Aspen路径到剪贴板

            selectedNode = obj.treeView.SelectedNodes;
            if isempty(selectedNode)
                return;
            end

            node = selectedNode(1);
            if isempty(node.NodeData) || ~isfield(node.NodeData, 'path')
                return;
            end

            try
                clipboard('copy', node.NodeData.path);
                obj.logMsg('info', sprintf('已复制路径: %s', node.NodeData.path));
            catch
                obj.logMsg('warning', '剪贴板操作不可用');
            end
        end

        function logMsg(obj, level, message)
            % logMsg 统一日志输出

            if ~isempty(obj.logger)
                switch lower(level)
                    case 'info'
                        obj.logger.info(message);
                    case 'warning'
                        obj.logger.warning(message);
                    case 'error'
                        obj.logger.error(message);
                    case 'debug'
                        obj.logger.debug(message);
                end
            end
        end
    end
end

