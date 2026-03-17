classdef ConfigWizard < handle
    % ConfigWizard 向导式配置流程
    %
    % 功能:
    %   - 分步骤的Aspen模型选择和配置
    %   - 变量定义向导
    %   - 目标和约束定义
    %   - 算法参数配置
    %   - 自动生成JSON配置
    %
    % 示例:
    %   wizard = ConfigWizard();
    %   wizard.start();
    %   config = wizard.getConfig();

    properties (Access = private)
        currentStep        % 当前向导步骤
        problem            % OptimizationProblem对象
        simulator          % Simulator配置
        algorithm          % Algorithm配置
        results            % 向导结果
        treeBrowser        % AspenTreeBrowser实例
        formulaWorkbench   % FormulaWorkbench实例

        % GUI组件
        wizardFigure       % 向导窗口
        stepPanels         % 各步的面板 cell array
        navigationButtons  % 导航按钮 struct
        stepIndicator      % 步骤指示器标签
        contentPanel       % 内容面板容器
        logger             % Logger实例
    end

    properties (Constant)
        STEP_SELECT_MODEL = 1
        STEP_DEFINE_VARIABLES = 2
        STEP_DEFINE_OBJECTIVES = 3
        STEP_DEFINE_CONSTRAINTS = 4
        STEP_SELECT_ALGORITHM = 5
        STEP_CONFIGURE_PARAMS = 6
        STEP_REVIEW = 7
        STEP_COMPLETE = 8
    end

    methods
        function obj = ConfigWizard()
            % ConfigWizard 构造函数

            obj.currentStep = obj.STEP_SELECT_MODEL;
            obj.problem = [];
            obj.simulator = struct();
            obj.algorithm = struct();
            obj.results = struct();

            try
                obj.treeBrowser = AspenTreeBrowser();
                obj.formulaWorkbench = [];
            catch
                obj.treeBrowser = [];
            end
        end

        function start(obj)
            % start 启动向导流程
            %
            % 说明:
            %   启动交互式配置向导

            obj.currentStep = obj.STEP_SELECT_MODEL;
        end

        function nextStep(obj)
            % nextStep 前进到下一步

            if obj.currentStep < obj.STEP_COMPLETE
                obj.currentStep = obj.currentStep + 1;
            end
        end

        function previousStep(obj)
            % previousStep 返回到上一步

            if obj.currentStep > obj.STEP_SELECT_MODEL
                obj.currentStep = obj.currentStep - 1;
            end
        end

        function step = getCurrentStep(obj)
            % getCurrentStep 获取当前步骤号

            step = obj.currentStep;
        end

        function description = getStepDescription(obj)
            % getStepDescription 获取当前步骤的描述

            descriptions = {
                '第1步: 选择Aspen模型文件',
                '第2步: 定义优化变量',
                '第3步: 定义目标函数',
                '第4步: 定义约束条件',
                '第5步: 选择优化算法',
                '第6步: 配置算法参数',
                '第7步: 检查和确认',
                '配置完成'
            };

            if obj.currentStep >= 1 && obj.currentStep <= length(descriptions)
                description = descriptions{obj.currentStep};
            else
                description = '未知步骤';
            end
        end

        function selectModelFile(obj, modelPath)
            % selectModelFile 选择Aspen模型文件（第1步）
            %
            % 输入:
            %   modelPath - 模型文件路径

            if ~isfile(modelPath)
                error('ConfigWizard:FileNotFound', '模型文件不存在: %s', modelPath);
            end

            % 尝试连接到Aspen模型
            try
                if ~isempty(obj.treeBrowser)
                    obj.treeBrowser.connect(modelPath);
                end
            catch ME
                warning('ConfigWizard:AspenConnectionFailed', ...
                    'Aspen连接失败: %s', ME.message);
            end

            % 创建优化问题对象
            [~, name, ~] = fileparts(modelPath);
            obj.problem = OptimizationProblem(name);

            % 初始化simulator配置
            obj.simulator = struct();
            obj.simulator.type = 'AspenPlus';
            obj.simulator.settings = struct('modelPath', modelPath);
            obj.simulator.nodeMapping = struct('variables', struct(), 'results', struct());
        end

        function addVariable(obj, varName, type, lowerBound, upperBound)
            % addVariable 添加优化变量（第2步）
            %
            % 输入:
            %   varName - 变量名称
            %   type - 变量类型 ('continuous'/'integer'/'discrete'/'categorical')
            %   lowerBound - 下界或离散值列表
            %   upperBound - 上界（仅用于连续/整数）

            if isempty(obj.problem)
                error('ConfigWizard:NoProblem', '请先选择模型文件');
            end

            switch lower(type)
                case {'continuous', 'integer'}
                    if nargin < 5
                        error('ConfigWizard:MissingBounds', '连续/整数变量需要边界');
                    end
                    obj.problem.addVariable(Variable(varName, type, [lowerBound, upperBound]));

                case {'discrete', 'categorical'}
                    if nargin < 5
                        error('ConfigWizard:MissingValues', '离散/分类变量需要值列表');
                    end
                    obj.problem.addVariable(Variable(varName, type, lowerBound));

                otherwise
                    error('ConfigWizard:InvalidType', '无效的变量类型: %s', type);
            end
        end

        function addObjective(obj, name, type, expression)
            % addObjective 添加目标函数（第3步）
            %
            % 输入:
            %   name - 目标函数名称
            %   type - 'minimize' 或 'maximize'
            %   expression - 表达式

            if isempty(obj.problem)
                error('ConfigWizard:NoProblem', '请先选择模型文件');
            end

            obj.problem.addObjective(Objective(name, type, expression));
        end

        function addConstraint(obj, name, expression)
            % addConstraint 添加约束条件（第4步）
            %
            % 输入:
            %   name - 约束条件名称
            %   expression - 约束表达式

            if isempty(obj.problem)
                error('ConfigWizard:NoProblem', '请先选择模型文件');
            end

            obj.problem.addConstraint(Constraint(name, 'inequality', expression));
        end

        function selectAlgorithm(obj, algorithmType, parameters)
            % selectAlgorithm 选择优化算法（第5-6步）
            %
            % 输入:
            %   algorithmType - 算法类型 ('NSGA-II', 'PSO', 'ANN-NSGA-II')
            %   parameters - 算法参数struct

            obj.algorithm = struct();
            obj.algorithm.type = algorithmType;

            if nargin < 3
                % 使用默认参数
                parameters = obj.getDefaultParameters(algorithmType);
            end

            obj.algorithm.parameters = parameters;
        end

        function config = generateConfig(obj)
            % generateConfig 生成完整的JSON配置（第7步）
            %
            % 输出:
            %   config - 配置struct

            if isempty(obj.problem)
                error('ConfigWizard:IncompletConfiguration', '配置不完整，缺少问题定义');
            end

            if isempty(obj.algorithm)
                error('ConfigWizard:IncompletConfiguration', '配置不完整，缺少算法选择');
            end

            % 构建配置结构
            config = struct();

            % 问题配置
            config.problem = obj.problem.toStruct();

            % 仿真器配置
            config.simulator = obj.simulator;

            % 算法配置
            config.algorithm = obj.algorithm;

            % 验证配置
            try
                ConfigValidator.validate(config);
                config.valid = true;
            catch ME
                config.valid = false;
                config.validationError = ME.message;
            end

            obj.results = config;
        end

        function config = getConfig(obj)
            % getConfig 获取生成的配置

            config = obj.results;
        end

        function success = saveConfigToFile(obj, filePath)
            % saveConfigToFile 将配置保存为JSON文件
            %
            % 输入:
            %   filePath - JSON文件路径
            %
            % 输出:
            %   success - 是否保存成功

            try
                config = obj.getConfig();

                % 转换为JSON
                jsonText = jsonencode(config);

                % 保存到文件
                fid = fopen(filePath, 'w');
                fprintf(fid, jsonText);
                fclose(fid);

                success = true;
            catch ME
                warning('ConfigWizard:SaveFailed', '配置保存失败: %s', ME.message);
                success = false;
            end
        end

        function preview = previewVariables(obj)
            % previewVariables 预览已定义的变量

            if isempty(obj.problem)
                preview = [];
                return;
            end

            varSet = obj.problem.getVariableSet();
            if isempty(varSet)
                preview = [];
                return;
            end

            variables = varSet.getVariables();
            preview = struct();

            for i = 1:length(variables)
                var = variables(i);
                preview(i).name = var.name;
                preview(i).type = var.type;

                if strcmp(var.type, 'continuous') || strcmp(var.type, 'integer')
                    preview(i).bounds = sprintf('[%g, %g]', var.lowerBound, var.upperBound);
                else
                    preview(i).values = var.values;
                end
            end
        end

        function preview = previewObjectives(obj)
            % previewObjectives 预览已定义的目标函数

            if isempty(obj.problem)
                preview = [];
                return;
            end

            nObj = obj.problem.getNumberOfObjectives();
            preview = struct();

            for i = 1:nObj
                obj_i = obj.problem.getObjective(i);
                if ~isempty(obj_i)
                    preview(i).name = obj_i.name;
                    preview(i).type = obj_i.type;
                    preview(i).expression = obj_i.expression;
                end
            end
        end
    end

    methods (Static)
        function params = getDefaultParameters(algorithmType)
            % getDefaultParameters 获取算法的默认参数

            params = struct();

            switch algorithmType
                case 'NSGA-II'
                    params.populationSize = 100;
                    params.maxGenerations = 250;
                    params.crossoverRate = 0.9;
                    params.mutationRate = 1/3;
                    params.crossoverDistIndex = 20;
                    params.mutationDistIndex = 20;

                case 'PSO'
                    params.swarmSize = 30;
                    params.maxIterations = 250;
                    params.w = 0.7298;
                    params.c1 = 1.49618;
                    params.c2 = 1.49618;
                    params.vMax = 0.2;

                case 'ANN-NSGA-II'
                    params.populationSize = 100;
                    params.maxGenerations = 250;
                    params.trainingSamples = 200;
                    params.surrogateType = 'poly2';

                otherwise
                    error('ConfigWizard:UnknownAlgorithm', '未知算法: %s', algorithmType);
            end
        end
    end

    methods
        function launchGUI(obj)
            % launchGUI 启动向导GUI界面
            %
            % 说明: 创建模态向导窗口，引导用户完成配置

            if exist('Logger', 'class')
                obj.logger = Logger.getLogger('ConfigWizard');
            else
                obj.logger = [];
            end

            obj.createWizardUI();
        end
    end

    methods (Access = private)
        function createWizardUI(obj)
            % createWizardUI 创建向导UI主框架

            obj.wizardFigure = uifigure('Name', 'MAPO 配置向导', ...
                'Position', [100, 100, 900, 700]);

            % 主布局
            mainGrid = uigridlayout(obj.wizardFigure, [3, 1]);
            mainGrid.RowHeight = {40, '1x', 50};
            mainGrid.Padding = [10, 10, 10, 10];

            % 顶部: 步骤指示器
            obj.stepIndicator = uilabel(mainGrid);
            obj.stepIndicator.FontSize = 14;
            obj.stepIndicator.FontWeight = 'bold';
            obj.stepIndicator.HorizontalAlignment = 'center';

            % 中间: 内容面板
            obj.contentPanel = uipanel(mainGrid);
            obj.contentPanel.BorderType = 'none';

            % 为每一步创建面板
            obj.stepPanels = cell(1, 7);
            for i = 1:7
                panel = uipanel(obj.contentPanel);
                panel.Position = [0, 0, 1, 1];
                panel.Units = 'normalized';
                panel.BorderType = 'none';
                panel.Visible = 'off';
                obj.stepPanels{i} = panel;
            end

            % 底部: 导航按钮
            navGrid = uigridlayout(mainGrid, [1, 4]);
            navGrid.ColumnWidth = {'1x', 'fit', 'fit', 'fit'};
            navGrid.RowHeight = {35};

            % 占位
            uilabel(navGrid, 'Text', '');

            obj.navigationButtons = struct();

            obj.navigationButtons.prevBtn = uibutton(navGrid, 'Text', '上一步');
            obj.navigationButtons.prevBtn.ButtonPushedFcn = @(~, ~) obj.goPreviousStep();
            obj.navigationButtons.prevBtn.Visible = 'off';

            obj.navigationButtons.nextBtn = uibutton(navGrid, 'Text', '下一步');
            obj.navigationButtons.nextBtn.ButtonPushedFcn = @(~, ~) obj.goNextStep();

            obj.navigationButtons.finishBtn = uibutton(navGrid, 'Text', '完成');
            obj.navigationButtons.finishBtn.ButtonPushedFcn = @(~, ~) obj.finishWizard();
            obj.navigationButtons.finishBtn.Visible = 'off';

            % 显示第1步
            obj.showStep(1);
        end

        function goNextStep(obj)
            % goNextStep 前进到下一步

            if obj.currentStep < obj.STEP_REVIEW
                obj.currentStep = obj.currentStep + 1;
            end

            if obj.currentStep >= obj.STEP_REVIEW
                obj.navigationButtons.nextBtn.Visible = 'off';
                obj.navigationButtons.finishBtn.Visible = 'on';
            end

            obj.navigationButtons.prevBtn.Visible = 'on';
            obj.showStep(obj.currentStep);
        end

        function goPreviousStep(obj)
            % goPreviousStep 返回到上一步

            if obj.currentStep > obj.STEP_SELECT_MODEL
                obj.currentStep = obj.currentStep - 1;
            end

            if obj.currentStep <= obj.STEP_SELECT_MODEL
                obj.navigationButtons.prevBtn.Visible = 'off';
            end

            if obj.currentStep < obj.STEP_REVIEW
                obj.navigationButtons.nextBtn.Visible = 'on';
                obj.navigationButtons.finishBtn.Visible = 'off';
            end

            obj.showStep(obj.currentStep);
        end

        function showStep(obj, step)
            % showStep 显示指定步骤

            % 隐藏所有面板
            for i = 1:7
                obj.stepPanels{i}.Visible = 'off';
            end

            % 更新步骤指示器
            stepTitles = {
                '第1步: 选择Aspen模型',
                '第2步: 定义优化变量',
                '第3步: 定义目标函数',
                '第4步: 定义约束条件',
                '第5步: 选择优化算法',
                '第6步: 配置算法参数',
                '第7步: 检查并确认'
            };
            obj.stepIndicator.Text = sprintf('%s (%d/7)', stepTitles{step}, step);

            % 清空并重建步骤面板内容
            delete(obj.stepPanels{step}.Children);

            switch step
                case 1
                    obj.buildStep1_SelectModel();
                case 2
                    obj.buildStep2_DefineVariables();
                case 3
                    obj.buildStep3_DefineObjectives();
                case 4
                    obj.buildStep4_DefineConstraints();
                case 5
                    obj.buildStep5_SelectAlgorithm();
                case 6
                    obj.buildStep6_ConfigureParams();
                case 7
                    obj.buildStep7_Review();
            end

            obj.stepPanels{step}.Visible = 'on';
        end

        function buildStep1_SelectModel(obj)
            % buildStep1_SelectModel 第1步: 选择Aspen模型

            panel = obj.stepPanels{1};
            grid = uigridlayout(panel, [3, 1]);
            grid.RowHeight = {'fit', 'fit', '1x'};
            grid.Padding = [20, 20, 20, 20];

            uilabel(grid, 'Text', '选择要优化的Aspen Plus模型文件 (.bkp):', ...
                'FontSize', 13);

            browseGrid = uigridlayout(grid, [1, 2]);
            browseGrid.ColumnWidth = {'1x', 'fit'};

            pathField = uieditfield(browseGrid, 'text');
            pathField.Editable = false;
            if ~isempty(obj.simulator) && isfield(obj.simulator, 'settings') ...
                    && isfield(obj.simulator.settings, 'modelPath')
                pathField.Value = obj.simulator.settings.modelPath;
            end
            pathField.Tag = 'modelPathField';

            browseBtn = uibutton(browseGrid, 'Text', '浏览...');
            browseBtn.ButtonPushedFcn = @(~, ~) obj.browseModelFile(pathField);

            uilabel(grid, 'Text', '选择模型文件后，系统将自动连接并读取模型结构。', ...
                'FontColor', [0.5, 0.5, 0.5]);
        end

        function browseModelFile(obj, pathField)
            % browseModelFile 浏览模型文件

            [file, path] = uigetfile('*.bkp', '选择Aspen模型文件');
            if file == 0
                return;
            end

            modelPath = fullfile(path, file);
            pathField.Value = modelPath;
            obj.selectModelFile(modelPath);
        end

        function buildStep2_DefineVariables(obj)
            % buildStep2_DefineVariables 第2步: 定义优化变量

            panel = obj.stepPanels{2};
            grid = uigridlayout(panel, [3, 1]);
            grid.RowHeight = {'fit', '1x', 'fit'};
            grid.Padding = [20, 20, 20, 20];

            uilabel(grid, 'Text', '定义优化变量 (决策变量):', 'FontSize', 13);

            varTable = uitable(grid);
            varTable.ColumnName = {'名称', '类型', '下界', '上界'};
            varTable.ColumnEditable = [true, true, true, true];
            varTable.Tag = 'varTable';

            btnGrid = uigridlayout(grid, [1, 2]);
            btnGrid.ColumnWidth = {'fit', 'fit'};

            addBtn = uibutton(btnGrid, 'Text', '添加变量');
            addBtn.ButtonPushedFcn = @(~, ~) obj.addVariableRow(varTable);

            delBtn = uibutton(btnGrid, 'Text', '删除选中');
            delBtn.ButtonPushedFcn = @(~, ~) obj.deleteSelectedRow(varTable);
        end

        function buildStep3_DefineObjectives(obj)
            % buildStep3_DefineObjectives 第3步: 定义目标函数

            panel = obj.stepPanels{3};
            grid = uigridlayout(panel, [3, 1]);
            grid.RowHeight = {'fit', '1x', 'fit'};
            grid.Padding = [20, 20, 20, 20];

            uilabel(grid, 'Text', '定义优化目标:', 'FontSize', 13);

            objTable = uitable(grid);
            objTable.ColumnName = {'名称', '方向', '表达式'};
            objTable.ColumnEditable = [true, true, true];
            objTable.Tag = 'objTable';

            btnGrid = uigridlayout(grid, [1, 2]);
            btnGrid.ColumnWidth = {'fit', 'fit'};

            addBtn = uibutton(btnGrid, 'Text', '添加目标');
            addBtn.ButtonPushedFcn = @(~, ~) obj.addObjectiveRow(objTable);

            delBtn = uibutton(btnGrid, 'Text', '删除选中');
            delBtn.ButtonPushedFcn = @(~, ~) obj.deleteSelectedRow(objTable);
        end

        function buildStep4_DefineConstraints(obj)
            % buildStep4_DefineConstraints 第4步: 定义约束条件

            panel = obj.stepPanels{4};
            grid = uigridlayout(panel, [3, 1]);
            grid.RowHeight = {'fit', '1x', 'fit'};
            grid.Padding = [20, 20, 20, 20];

            uilabel(grid, 'Text', '定义约束条件 (可选):', 'FontSize', 13);

            conTable = uitable(grid);
            conTable.ColumnName = {'名称', '类型', '表达式'};
            conTable.ColumnEditable = [true, true, true];
            conTable.Tag = 'conTable';

            btnGrid = uigridlayout(grid, [1, 2]);
            btnGrid.ColumnWidth = {'fit', 'fit'};

            addBtn = uibutton(btnGrid, 'Text', '添加约束');
            addBtn.ButtonPushedFcn = @(~, ~) obj.addConstraintRow(conTable);

            delBtn = uibutton(btnGrid, 'Text', '删除选中');
            delBtn.ButtonPushedFcn = @(~, ~) obj.deleteSelectedRow(conTable);
        end

        function buildStep5_SelectAlgorithm(obj)
            % buildStep5_SelectAlgorithm 第5步: 选择优化算法

            panel = obj.stepPanels{5};
            grid = uigridlayout(panel, [4, 1]);
            grid.RowHeight = {'fit', 'fit', 'fit', '1x'};
            grid.Padding = [20, 20, 20, 20];

            uilabel(grid, 'Text', '选择优化算法:', 'FontSize', 13);

            algoDropDown = uidropdown(grid);
            algoDropDown.Items = {'NSGA-II', 'PSO', 'ANN-NSGA-II'};
            algoDropDown.Value = 'NSGA-II';
            algoDropDown.Tag = 'algoDropDown';

            % 算法说明
            descArea = uitextarea(grid);
            descArea.Editable = false;
            descArea.Value = {'NSGA-II: 快速非支配排序遗传算法，适合多目标优化。'};
            descArea.Tag = 'algoDesc';

            algoDropDown.ValueChangedFcn = @(src, ~) obj.updateAlgoDescription(src, descArea);

            uilabel(grid, 'Text', '');
        end

        function buildStep6_ConfigureParams(obj)
            % buildStep6_ConfigureParams 第6步: 配置算法参数

            panel = obj.stepPanels{6};
            grid = uigridlayout(panel, [2, 1]);
            grid.RowHeight = {'fit', '1x'};
            grid.Padding = [20, 20, 20, 20];

            uilabel(grid, 'Text', '配置算法参数 (使用默认值或自定义):', 'FontSize', 13);

            paramTable = uitable(grid);
            paramTable.ColumnName = {'参数', '值', '说明'};
            paramTable.ColumnEditable = [false, true, false];
            paramTable.Tag = 'paramTable';

            % 填充默认参数
            algoType = 'NSGA-II';
            if ~isempty(obj.algorithm) && isfield(obj.algorithm, 'type')
                algoType = obj.algorithm.type;
            end
            params = ConfigWizard.getDefaultParameters(algoType);
            fields = fieldnames(params);
            data = cell(length(fields), 3);
            for i = 1:length(fields)
                data{i, 1} = fields{i};
                data{i, 2} = num2str(params.(fields{i}));
                data{i, 3} = '';
            end
            paramTable.Data = data;
        end

        function buildStep7_Review(obj)
            % buildStep7_Review 第7步: 检查并确认

            panel = obj.stepPanels{7};
            grid = uigridlayout(panel, [2, 1]);
            grid.RowHeight = {'fit', '1x'};
            grid.Padding = [20, 20, 20, 20];

            uilabel(grid, 'Text', '配置总结 - 请确认以下设置:', 'FontSize', 13);

            reviewArea = uitextarea(grid);
            reviewArea.Editable = false;

            % 生成总结
            summary = {};
            summary{end+1} = '=== 配置总结 ===';

            if ~isempty(obj.simulator) && isfield(obj.simulator, 'settings')
                summary{end+1} = sprintf('模型: %s', obj.simulator.settings.modelPath);
            end

            if ~isempty(obj.problem)
                summary{end+1} = sprintf('变量数: %d', obj.problem.getNumberOfVariables());
                summary{end+1} = sprintf('目标数: %d', obj.problem.getNumberOfObjectives());
                summary{end+1} = sprintf('约束数: %d', obj.problem.getNumberOfConstraints());
            end

            if ~isempty(obj.algorithm) && isfield(obj.algorithm, 'type')
                summary{end+1} = sprintf('算法: %s', obj.algorithm.type);
            end

            summary{end+1} = '';
            summary{end+1} = '点击"完成"生成配置文件。';

            reviewArea.Value = summary;
        end

        function finishWizard(obj)
            % finishWizard 完成向导，生成配置

            try
                config = obj.generateConfig();

                % 询问保存路径
                [file, path] = uiputfile('case_config.json', '保存配置文件');
                if file ~= 0
                    filePath = fullfile(path, file);
                    obj.saveConfigToFile(filePath);
                    uialert(obj.wizardFigure, sprintf('配置已保存到: %s', filePath), ...
                        '保存成功', 'Icon', 'success');
                end

                % 关闭向导窗口
                delete(obj.wizardFigure);

            catch ME
                uialert(obj.wizardFigure, sprintf('生成配置失败: %s', ME.message), ...
                    '错误', 'Icon', 'error');
            end
        end

        function addVariableRow(~, table)
            % addVariableRow 添加变量行
            data = table.Data;
            if isempty(data)
                data = {'var1', 'continuous', '0', '10'};
            else
                data = [data; {sprintf('var%d', size(data, 1) + 1), 'continuous', '0', '10'}];
            end
            table.Data = data;
        end

        function addObjectiveRow(~, table)
            % addObjectiveRow 添加目标行
            data = table.Data;
            if isempty(data)
                data = {'obj1', 'minimize', ''};
            else
                data = [data; {sprintf('obj%d', size(data, 1) + 1), 'minimize', ''}];
            end
            table.Data = data;
        end

        function addConstraintRow(~, table)
            % addConstraintRow 添加约束行
            data = table.Data;
            if isempty(data)
                data = {'con1', 'inequality', ''};
            else
                data = [data; {sprintf('con%d', size(data, 1) + 1), 'inequality', ''}];
            end
            table.Data = data;
        end

        function deleteSelectedRow(~, table)
            % deleteSelectedRow 删除选中行
            data = table.Data;
            if isempty(data)
                return;
            end
            % 删除最后一行 (MATLAB uitable没有直接的选中行API)
            if size(data, 1) > 0
                data(end, :) = [];
                table.Data = data;
            end
        end

        function updateAlgoDescription(~, dropdown, descArea)
            % updateAlgoDescription 更新算法说明

            switch dropdown.Value
                case 'NSGA-II'
                    descArea.Value = {'NSGA-II: 快速非支配排序遗传算法。', ...
                        '适合多目标优化，支持2-3个目标。', ...
                        '推荐种群大小: 100-200'};
                case 'PSO'
                    descArea.Value = {'PSO: 粒子群优化算法。', ...
                        '适合单目标或简单多目标问题。', ...
                        '推荐粒子数: 30-50'};
                case 'ANN-NSGA-II'
                    descArea.Value = {'ANN-NSGA-II: 代理辅助NSGA-II。', ...
                        '适合仿真耗时长的问题，用ANN代理加速。', ...
                        '需要Deep Learning Toolbox'};
            end
        end
    end
end
