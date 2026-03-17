classdef FormulaWorkbench < handle
    % FormulaWorkbench 公式工作台
    %
    % 功能:
    %   - 管理优化问题的目标函数和约束表达式
    %   - 编辑和验证表达式
    %   - 基于试算结果预览目标和约束的当前值
    %   - 提供表达式的智能补全
    %
    % 示例:
    %   wb = FormulaWorkbench(problem);
    %   wb.addObjective('profit', 'maximize', 'result.Revenue - result.Cost');
    %   wb.previewObjectives(dryRunResult);

    properties (Access = private)
        problem             % OptimizationProblem对象
        objectives          % 目标函数cell数组
        constraints         % 约束条件cell数组
        derivedVariables    % 派生变量定义
        expressionEngine    % 表达式引擎
        lastEvalContext     % 上一次评估的上下文
    end

    methods
        function obj = FormulaWorkbench(problem)
            % FormulaWorkbench 构造函数
            %
            % 输入:
            %   problem - OptimizationProblem对象

            if nargin < 1
                error('FormulaWorkbench:MissingProblem', '需要提供OptimizationProblem对象');
            end

            if ~isa(problem, 'OptimizationProblem')
                error('FormulaWorkbench:InvalidType', '输入必须是OptimizationProblem对象');
            end

            obj.problem = problem;
            obj.objectives = {};
            obj.constraints = {};
            obj.derivedVariables = {};

            try
                obj.expressionEngine = ExpressionEngine();
            catch
                % 如果ExpressionEngine不可用，设为空
                obj.expressionEngine = [];
            end
        end

        function addObjective(obj, name, type, expression)
            % addObjective 添加目标函数
            %
            % 输入:
            %   name - 目标函数名称
            %   type - 'minimize' 或 'maximize'
            %   expression - 表达式字符串
            %
            % 示例:
            %   wb.addObjective('profit', 'maximize', 'result.Revenue - result.Cost');

            if ~ismember(lower(type), {'minimize', 'maximize'})
                error('FormulaWorkbench:InvalidType', '目标类型必须是 minimize 或 maximize');
            end

            % 验证表达式
            if ~obj.validateExpression(expression)
                warning('FormulaWorkbench:InvalidExpression', ...
                    '表达式 "%s" 可能存在语法错误，但仍会添加', name);
            end

            entry = struct();
            entry.name = name;
            entry.type = lower(type);
            entry.expression = expression;
            entry.enabled = true;
            entry.notes = '';

            % 检查是否已存在
            for i = 1:length(obj.objectives)
                if strcmp(obj.objectives{i}.name, name)
                    obj.objectives{i} = entry;
                    return;
                end
            end

            obj.objectives{end+1} = entry;
        end

        function addConstraint(obj, name, expression)
            % addConstraint 添加约束条件
            %
            % 输入:
            %   name - 约束条件名称
            %   expression - 约束表达式（应为不等式或等式形式）
            %
            % 示例:
            %   wb.addConstraint('min_purity', 'result.PURITY >= 0.99');

            % 验证表达式
            if ~obj.validateExpression(expression)
                warning('FormulaWorkbench:InvalidExpression', ...
                    '约束表达式 "%s" 可能存在语法错误，但仍会添加', name);
            end

            entry = struct();
            entry.name = name;
            entry.expression = expression;
            entry.enabled = true;
            entry.notes = '';

            % 检查是否已存在
            for i = 1:length(obj.constraints)
                if strcmp(obj.constraints{i}.name, name)
                    obj.constraints{i} = entry;
                    return;
                end
            end

            obj.constraints{end+1} = entry;
        end

        function removeObjective(obj, name)
            % removeObjective 移除目标函数

            for i = 1:length(obj.objectives)
                if strcmp(obj.objectives{i}.name, name)
                    obj.objectives(i) = [];
                    return;
                end
            end
        end

        function removeConstraint(obj, name)
            % removeConstraint 移除约束条件

            for i = 1:length(obj.constraints)
                if strcmp(obj.constraints{i}.name, name)
                    obj.constraints(i) = [];
                    return;
                end
            end
        end

        function valid = validateExpression(obj, expression)
            % validateExpression 验证表达式的语法
            %
            % 输入:
            %   expression - 表达式字符串
            %
            % 输出:
            %   valid - 布尔值

            valid = true;

            if isempty(expression)
                valid = false;
                return;
            end

            % 检查基本语法
            if ~contains(expression, '.') && ~contains(expression, '(')
                valid = false;
                return;
            end

            % 如果有ExpressionEngine，使用它验证
            if ~isempty(obj.expressionEngine)
                try
                    % 这只是检查，不实际求值
                    tokens = obj.expressionEngine.tokenize(expression);
                    if isempty(tokens)
                        valid = false;
                    end
                catch
                    valid = false;
                end
            end
        end

        function preview = previewObjectives(obj, dryRunResult)
            % previewObjectives 基于试算结果预览目标值
            %
            % 输入:
            %   dryRunResult - struct，包含目标值、约束值等试算结果
            %
            % 输出:
            %   preview - struct数组，每个元素包含目标名称和预览值
            %
            % 示例:
            %   preview = wb.previewObjectives(dryRunResult);

            preview = struct();

            if isempty(obj.objectives)
                return;
            end

            if ~isstruct(dryRunResult)
                error('FormulaWorkbench:InvalidInput', 'dryRunResult必须是struct');
            end

            for i = 1:length(obj.objectives)
                obj_entry = obj.objectives{i};

                preview(i).name = obj_entry.name;
                preview(i).type = obj_entry.type;
                preview(i).expression = obj_entry.expression;

                % 尝试评估表达式
                try
                    % 简单的字符串替换方式（不使用ExpressionEngine）
                    result_val = obj.evaluateSimple(obj_entry.expression, dryRunResult);
                    preview(i).value = result_val;
                    preview(i).success = true;
                catch ME
                    preview(i).value = NaN;
                    preview(i).success = false;
                    preview(i).error = ME.message;
                end
            end
        end

        function preview = previewConstraints(obj, dryRunResult)
            % previewConstraints 基于试算结果预览约束值
            %
            % 输入:
            %   dryRunResult - struct，包含约束值等试算结果
            %
            % 输出:
            %   preview - struct数组，包含约束值和可行性

            preview = struct();

            if isempty(obj.constraints)
                return;
            end

            if ~isstruct(dryRunResult)
                error('FormulaWorkbench:InvalidInput', 'dryRunResult必须是struct');
            end

            for i = 1:length(obj.constraints)
                constr_entry = obj.constraints{i};

                preview(i).name = constr_entry.name;
                preview(i).expression = constr_entry.expression;

                % 尝试评估表达式
                try
                    result_val = obj.evaluateSimple(constr_entry.expression, dryRunResult);
                    preview(i).value = result_val;
                    preview(i).feasible = result_val <= 0;  % 假设约束形式为 g(x) <= 0
                    preview(i).success = true;
                catch ME
                    preview(i).value = NaN;
                    preview(i).feasible = false;
                    preview(i).success = false;
                    preview(i).error = ME.message;
                end
            end
        end

        function vars = getAvailableVariables(obj)
            % getAvailableVariables 获取可用的变量和参数列表
            %
            % 输出:
            %   vars - struct数组，包含变量类型和名称
            %
            % 说明:
            %   用于GUI中的智能补全

            vars = struct();
            idx = 1;

            % 添加决策变量
            if ~isempty(obj.problem)
                varSet = obj.problem.getVariableSet();
                if ~isempty(varSet)
                    variables = varSet.getVariables();
                    for i = 1:length(variables)
                        vars(idx).name = variables(i).name;
                        vars(idx).type = 'variable';
                        vars(idx).prefix = 'x';
                        vars(idx).fullName = sprintf('x.%s', variables(i).name);
                        idx = idx + 1;
                    end
                end
            end

            % 添加派生变量
            for i = 1:length(obj.derivedVariables)
                vars(idx).name = obj.derivedVariables{i}.name;
                vars(idx).type = 'derived';
                vars(idx).prefix = 'derived';
                vars(idx).fullName = sprintf('derived.%s', obj.derivedVariables{i}.name);
                idx = idx + 1;
            end
        end

        function getSuggestions(obj, prefix)
            % getSuggestions 获取表达式补全建议
            %
            % 输入:
            %   prefix - 部分表达式前缀
            %
            % 输出:
            %   suggestions - 建议的表达式cell数组

            suggestions = {};

            % 提供通用函数建议
            if contains(prefix, '(')
                functions = {'min(', 'max(', 'abs(', 'sqrt(', 'log(', 'exp(', 'if(', 'sum('};
                suggestions = functions;
            end
        end

        function objectives = getObjectives(obj)
            % getObjectives 获取所有目标函数

            objectives = obj.objectives;
        end

        function constraints = getConstraints(obj)
            % getConstraints 获取所有约束条件

            constraints = obj.constraints;
        end

        function clearAll(obj)
            % clearAll 清除所有目标和约束

            obj.objectives = {};
            obj.constraints = {};
        end
    end

    methods (Access = private)
        function result = evaluateSimple(obj, expression, context)
            % evaluateSimple 简单的表达式评估
            %
            % 用于预览，不需要完整的表达式引擎

            % 这是一个简化的实现，仅用于演示
            % 实际应使用ExpressionEngine
            result = 0;

            % 如果有ExpressionEngine，使用它
            if ~isempty(obj.expressionEngine) && isstruct(context)
                try
                    result = obj.expressionEngine.evaluate(expression, context);
                    return;
                catch
                end
            end

            % 简单的字符串替换（有限支持）
            expr = expression;

            % 替换result.*
            if isfield(context, 'objectives')
                expr = strrep(expr, 'result.', 'context.');
            end

            throw(MException('FormulaWorkbench:EvaluationNotSupported', ...
                '完整的表达式评估需要ExpressionEngine支持'));
        end
    end
end
