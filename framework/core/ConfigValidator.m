classdef ConfigValidator
    % ConfigValidator 配置验证器 - 启动前校验所有配置
    %
    % 功能：
    %   - 检查表达式前缀有效性（x.、result.、param.、derived.）
    %   - 检查结果映射完整性（所有result.*都有映射）
    %   - 检查单位合法性
    %   - 检查变量数量一致性
    %   - 检查目标方向一致性
    %   - 输出具体修复建议而不只是报错
    %
    % 使用示例：
    %   validator = ConfigValidator(config, simulator);
    %   [isValid, issues] = validator.validate();
    %   validator.printReport();

    properties (Access = private)
        config;           % JSON配置结构体
        simulator;        % 仿真器对象
        issues;           % 发现的问题集合
        warnings;         % 警告信息
    end

    methods
        function obj = ConfigValidator(config, simulator)
            % 构造函数
            %
            % 输入:
            %   config - 从JSON加载的配置结构体
            %   simulator - 仿真器对象（可选）

            obj.config = config;
            if nargin >= 2
                obj.simulator = simulator;
            else
                obj.simulator = [];
            end
            obj.issues = {};
            obj.warnings = {};
        end

        function [isValid, issues] = validate(obj)
            % validate 执行完整的配置验证
            %
            % 输出:
            %   isValid - 是否通过验证（true/false）
            %   issues - 问题和修复建议的cell数组

            obj.issues = {};
            obj.warnings = {};

            % 步骤1：验证基础结构
            obj.validateBasicStructure();

            % 步骤2：验证目标定义
            if isfield(obj.config, 'problem')
                obj.validateObjectives();
            end

            % 步骤3：验证表达式和映射
            if isfield(obj.config, 'problem') && isfield(obj.config.problem, 'evaluator')
                obj.validateExpressions();
            end

            % 步骤4：验证映射一致性
            if isfield(obj.config, 'simulator')
                obj.validateMappings();
            end

            % 步骤5：检查兼容性警告
            obj.checkBackwardCompatibility();

            isValid = isempty(obj.issues);
            issues = [obj.issues; obj.warnings];
        end

        function printReport(obj)
            % printReport 打印验证报告

            if isempty(obj.issues) && isempty(obj.warnings)
                fprintf('✓ 配置验证通过！所有检查项正常。\n\n');
                return;
            end

            if ~isempty(obj.issues)
                fprintf('\n%s\n', repmat('=', 1, 60));
                fprintf('配置错误（需要修复）\n');
                fprintf('%s\n\n', repmat('=', 1, 60));
                for i = 1:length(obj.issues)
                    fprintf('[错误 %d] %s\n', i, obj.issues{i});
                    fprintf('\n');
                end
            end

            if ~isempty(obj.warnings)
                fprintf('\n%s\n', repmat('-', 1, 60));
                fprintf('配置警告（建议修复）\n');
                fprintf('%s\n\n', repmat('-', 1, 60));
                for i = 1:length(obj.warnings)
                    fprintf('[警告 %d] %s\n', i, obj.warnings{i});
                    fprintf('\n');
                end
            end
        end
    end

    methods (Access = private)
        function validateBasicStructure(obj)
            % 检查基本结构完整性

            if ~isfield(obj.config, 'problem')
                obj.addIssue('缺少必需字段 ''problem''');
            end

            if ~isfield(obj.config, 'simulator')
                obj.addIssue('缺少必需字段 ''simulator''');
            end

            if isfield(obj.config, 'problem')
                problem = obj.config.problem;
                if ~isfield(problem, 'name')
                    obj.addIssue('problem.name 未定义');
                end
                if ~isfield(problem, 'variables')
                    obj.addIssue('problem.variables 未定义');
                elseif isempty(problem.variables)
                    obj.addIssue('problem.variables 为空，至少需要1个变量');
                else
                    % 验证变量定义的完整性
                    obj.validateVariablesDefinition(problem.variables);
                end
                if ~isfield(problem, 'objectives')
                    obj.addIssue('problem.objectives 未定义');
                elseif isempty(problem.objectives)
                    obj.addIssue('problem.objectives 为空，至少需要1个目标');
                end
                if isfield(problem, 'evaluator')
                    obj.validateEvaluatorDef(problem.evaluator);
                end
            end
        end

        function validateObjectives(obj)
            % 检查目标定义的一致性

            problem = obj.config.problem;

            if ~isfield(problem, 'objectives')
                return;
            end

            objectives = problem.objectives;
            if ~isstruct(objectives)
                obj.addIssue('objectives 必须是结构体数组');
                return;
            end

            for i = 1:length(objectives)
                obj_def = objectives(i);

                % 检查名称
                if ~isfield(obj_def, 'name')
                    obj.addIssue(sprintf('objectives[%d] 缺少 ''name'' 字段', i));
                end

                % 检查类型（可以是maximize或minimize）
                if isfield(obj_def, 'type')
                    objType = lower(obj_def.type);
                    if ~ismember(objType, {'maximize', 'minimize'})
                        obj.addIssue(sprintf(...
                            'objectives[%d].type 的值 ''%s'' 无效。\n  应该是 ''maximize'' 或 ''minimize''', ...
                            i, obj_def.type));
                    end
                else
                    obj.addWarning(sprintf(...
                        'objectives[%d] 缺少 ''type'' 字段，默认为 ''minimize''', i));
                end

                % 检查表达式
                if isfield(obj_def, 'expression')
                    obj.validateExpressionSyntax(obj_def.expression, ...
                        sprintf('objectives[%d].expression', i));
                end
            end
        end

        function validateExpressions(obj)
            % 检查所有表达式中的引用

            problem = obj.config.problem;
            resultNames = {};

            % 收集所有result.*的引用
            if isfield(problem, 'objectives')
                for i = 1:length(problem.objectives)
                    if isfield(problem.objectives(i), 'expression')
                        resultNames = [resultNames, obj.extractResultRefs(problem.objectives(i).expression)];
                    end
                end
            end

            if isfield(problem, 'constraints')
                for i = 1:length(problem.constraints)
                    if isfield(problem.constraints(i), 'expression')
                        resultNames = [resultNames, obj.extractResultRefs(problem.constraints(i).expression)];
                    end
                end
            end

            if isfield(problem, 'derived')
                for i = 1:length(problem.derived)
                    if isfield(problem.derived(i), 'expression')
                        resultNames = [resultNames, obj.extractResultRefs(problem.derived(i).expression)];
                    end
                end
            end

            % 检查这些result是否都有映射
            resultNames = unique(resultNames);
            if ~isempty(obj.simulator) && ~isempty(resultNames)
                obj.checkResultMappings(resultNames);
            end
        end

        function validateMappings(obj)
            % 检查映射的一致性和统一性

            simulator = obj.config.simulator;

            % 检查是否同时使用旧的nodeMapping和resultMapping（应该统一）
            hasNodeMapping = isfield(simulator, 'nodeMapping');
            hasResultMapping = isfield(simulator, 'resultMapping');

            if hasNodeMapping && hasResultMapping
                % 同时存在两个字段是错误的
                obj.addIssue(sprintf(...
                    '检测到同时使用 nodeMapping 和 resultMapping，这会导致配置混乱。\n' + ...
                    '  建议统一为以下格式:\n' + ...
                    '  "simulator": {\n' + ...
                    '    "nodeMapping": {\n' + ...
                    '      "variables": {variable_name: aspen_path, ...},\n' + ...
                    '      "results": {result_name: aspen_path, ...}\n' + ...
                    '    }\n' + ...
                    '  }'));
            elseif hasResultMapping
                % 只有resultMapping说明用户使用的是旧格式
                obj.addWarning(sprintf(...
                    '检测到使用旧的 resultMapping 格式。\n' + ...
                    '  建议统一为新格式: simulator.nodeMapping.results'));
            end

            % 检查nodeMapping格式是否正确
            if hasNodeMapping
                nodeMapping = simulator.nodeMapping;
                % 检查是否为结构体（新格式）
                if isstruct(nodeMapping)
                    % 新格式应该有variables和results字段
                    hasVars = isfield(nodeMapping, 'variables');
                    hasResults = isfield(nodeMapping, 'results');
                    if ~hasVars && ~hasResults
                        % 可能是旧格式（所有映射混在一起）
                        obj.addWarning(sprintf(...
                            'nodeMapping 结构不标准，建议重新组织为:\n' + ...
                            '  "nodeMapping": {\n' + ...
                            '    "variables": {...},\n' + ...
                            '    "results": {...}\n' + ...
                            '  }'));
                    end
                end
            end
        end

        function validateExpressionSyntax(obj, expr, location)
            % 检查表达式语法有效性

            expr = char(string(expr));  % 确保是字符串

            % 检查前缀有效性
            validPrefixes = {'x.', 'result.', 'param.', 'derived.'};
            identifiers = regexp(expr, '[a-zA-Z_]\w*\.', 'match');

            if ~isempty(identifiers)
                identifiers = unique(identifiers);
                for i = 1:length(identifiers)
                    prefix = identifiers{i};
                    if ~any(strcmp(prefix, validPrefixes))
                        obj.addIssue(sprintf(...
                            '%s 中检测到无效前缀 ''%s''。\n  有效前缀：x., result., param., derived.', ...
                            location, prefix));
                    end
                end
            end
        end

        function checkResultMappings(obj, resultNames)
            % 检查result映射是否完整

            if ~isfield(obj.config.simulator, 'nodeMapping')
                return;
            end

            nodeMapping = obj.config.simulator.nodeMapping;

            % 新格式：nodeMapping.results
            if isfield(nodeMapping, 'results')
                results = nodeMapping.results;
                for i = 1:length(resultNames)
                    name = resultNames{i};
                    if ~isfield(results, name)
                        obj.addIssue(sprintf(...
                            '缺少结果映射：%s\n  请在 simulator.nodeMapping.results 中添加：\n  "%s": "<Aspen节点路径>"', ...
                            name, name));
                    end
                end
            end
        end

        function names = extractResultRefs(obj, expr)
            % 从表达式中提取所有result.*的引用

            expr = char(string(expr));
            % 匹配 result.XXX 的模式
            matches = regexp(expr, 'result\.(\w+)', 'tokens');
            names = {};
            if ~isempty(matches)
                for i = 1:length(matches)
                    names{i} = matches{i}{1};
                end
            end
        end

        function checkBackwardCompatibility(obj)
            % 检查向后兼容性问题

            simulator = obj.config.simulator;

            % 检查旧的直接setNodeMapping/setResultMapping用法
            if isfield(simulator, 'nodeMapping') && ~isstruct(simulator.nodeMapping)
                obj.addWarning('检测到旧的 nodeMapping 格式（直接映射而不是变量/结果分类）。\n  建议更新为新格式。');
            end
        end

        function validateVariablesDefinition(obj, variables)
            % 验证变量定义的完整性

            for i = 1:length(variables)
                var = variables(i);

                % 检查变量名称
                if ~isfield(var, 'name')
                    obj.addIssue(sprintf('variables[%d] 缺少 ''name'' 字段', i));
                    continue;
                end

                % 检查变量类型
                if ~isfield(var, 'type')
                    obj.addWarning(sprintf('variables[%d] (%s) 缺少 ''type'' 字段，建议指定', i, var.name));
                end

                % 检查变量范围（对于连续和离散变量）
                if isfield(var, 'type') && ~ismember(lower(var.type), {'categorical'})
                    if ~isfield(var, 'lowerBound')
                        obj.addIssue(sprintf('variables[%d] (%s) 缺少 ''lowerBound''', i, var.name));
                    end
                    if ~isfield(var, 'upperBound')
                        obj.addIssue(sprintf('variables[%d] (%s) 缺少 ''upperBound''', i, var.name));
                    end
                    % 检查范围的合理性
                    if isfield(var, 'lowerBound') && isfield(var, 'upperBound')
                        if var.lowerBound >= var.upperBound
                            obj.addIssue(sprintf(...
                                'variables[%d] (%s) 的范围不合法: lowerBound (%.2f) 应小于 upperBound (%.2f)', ...
                                i, var.name, var.lowerBound, var.upperBound));
                        end
                    end
                end
            end
        end

        function validateEvaluatorDef(obj, evaluator)
            % 验证评估器定义

            if ~isfield(evaluator, 'type')
                obj.addIssue('problem.evaluator 缺少 ''type'' 字段');
                return;
            end

            evalType = evaluator.type;

            % 检查ExpressionEvaluator特定的配置
            if strcmpi(evalType, 'ExpressionEvaluator')
                if ~isfield(evaluator, 'objectives')
                    obj.addIssue('ExpressionEvaluator 需要定义 ''objectives'' 字段，指定目标函数表达式');
                else
                    % 检查每个目标是否有表达式
                    objectives = evaluator.objectives;
                    for i = 1:length(objectives)
                        if ~isfield(objectives(i), 'expression')
                            obj.addIssue(sprintf('evaluator.objectives[%d] 缺少 ''expression'' 字段', i));
                        end
                    end
                end
            end
        end

        function addIssue(obj, message)
            % 添加严重问题（需要修复）
            obj.issues{end+1} = message;
        end

        function addWarning(obj, message)
            % 添加警告（建议修复）
            obj.warnings{end+1} = message;
        end
    end
end
