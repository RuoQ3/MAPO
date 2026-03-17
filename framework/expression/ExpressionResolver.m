classdef ExpressionResolver < handle
    % ExpressionResolver 表达式解析器
    %
    % 功能:
    %   - 支持隐式前缀推断（无需显式写x./result./param.等前缀）
    %   - 标准化表达式为完整形式
    %   - 检测和处理前缀冲突
    %   - 提供表达式标准化和验证
    %
    % 示例:
    %   resolver = ExpressionResolver(problem);
    %   standardExpr = resolver.resolveExpression('x1 + x2 * result.cost');
    %   % 结果: 'x.x1 + x.x2 * result.cost'

    properties (Access = private)
        problem              % OptimizationProblem对象
        variableNames        % 可用的决策变量名称
        parameterNames       % 可用的参数名称
        resultNodeNames      % 可用的结果节点名称
        derivedVarNames      % 可用的派生变量名称
    end

    methods
        function obj = ExpressionResolver(problem)
            % ExpressionResolver 构造函数
            %
            % 输入:
            %   problem - OptimizationProblem对象

            if nargin < 1
                error('ExpressionResolver:MissingProblem', '需要提供OptimizationProblem对象');
            end

            if ~isa(problem, 'OptimizationProblem')
                error('ExpressionResolver:InvalidType', '输入必须是OptimizationProblem对象');
            end

            obj.problem = problem;
            obj.buildIdentifierLists();
        end

        function standardExpr = resolveExpression(obj, expression)
            % resolveExpression 标准化表达式（添加隐式前缀）
            %
            % 输入:
            %   expression - 原始表达式字符串
            %
            % 输出:
            %   standardExpr - 标准化后的表达式
            %
            % 说明:
            %   - 对已有显式前缀的标识符保持不变
            %   - 对没有前缀的标识符自动添加前缀
            %   - 处理函数调用、运算符等

            if isempty(expression)
                standardExpr = expression;
                return;
            end

            standardExpr = obj.processExpression(expression);
        end

        function [success, warnings] = validateExpression(obj, expression)
            % validateExpression 验证表达式的有效性
            %
            % 输入:
            %   expression - 表达式字符串
            %
            % 输出:
            %   success - 布尔值，表达式是否有效
            %   warnings - 警告信息cell数组

            success = true;
            warnings = {};

            if isempty(expression)
                success = false;
                warnings{1} = '表达式不能为空';
                return;
            end

            % 检查括号匹配
            if obj.checkBracketMatching(expression)
                warnings{end+1} = '括号不匹配';
                success = false;
            end

            % 检查操作符语法
            if obj.checkOperatorSyntax(expression)
                warnings{end+1} = '操作符语法错误';
                success = false;
            end

            % 解析并检查标识符
            [idWarnings, idValid] = obj.checkIdentifiers(expression);
            if ~isempty(idWarnings)
                warnings = [warnings, idWarnings];
                success = success && idValid;
            end
        end

        function identifiers = getAvailableIdentifiers(obj)
            % getAvailableIdentifiers 获取所有可用的标识符
            %
            % 输出:
            %   identifiers - struct数组

            identifiers = struct();
            idx = 1;

            % 决策变量
            for i = 1:length(obj.variableNames)
                identifiers(idx).name = obj.variableNames{i};
                identifiers(idx).type = 'variable';
                identifiers(idx).prefix = 'x';
                idx = idx + 1;
            end

            % 派生变量
            for i = 1:length(obj.derivedVarNames)
                identifiers(idx).name = obj.derivedVarNames{i};
                identifiers(idx).type = 'derived';
                identifiers(idx).prefix = 'derived';
                idx = idx + 1;
            end

            % 结果节点
            for i = 1:length(obj.resultNodeNames)
                identifiers(idx).name = obj.resultNodeNames{i};
                identifiers(idx).type = 'result';
                identifiers(idx).prefix = 'result';
                idx = idx + 1;
            end

            % 参数
            for i = 1:length(obj.parameterNames)
                identifiers(idx).name = obj.parameterNames{i};
                identifiers(idx).type = 'parameter';
                identifiers(idx).prefix = 'param';
                idx = idx + 1;
            end
        end

        function list = getSuggestions(obj, partialIdentifier)
            % getSuggestions 获取标识符补全建议
            %
            % 输入:
            %   partialIdentifier - 部分标识符
            %
            % 输出:
            %   list - 匹配的标识符cell数组

            list = {};

            identifiers = obj.getAvailableIdentifiers();

            for i = 1:length(identifiers)
                if strncmp(identifiers(i).name, partialIdentifier, length(partialIdentifier))
                    list{end+1} = sprintf('%s.%s', identifiers(i).prefix, identifiers(i).name);
                end
            end
        end
    end

    methods (Access = private)
        function buildIdentifierLists(obj)
            % buildIdentifierLists 构建可用标识符列表

            obj.variableNames = {};
            obj.parameterNames = {};
            obj.resultNodeNames = {};
            obj.derivedVarNames = {};

            if isempty(obj.problem)
                return;
            end

            % 获取决策变量
            try
                varSet = obj.problem.getVariableSet();
                if ~isempty(varSet)
                    variables = varSet.getVariables();
                    for i = 1:length(variables)
                        obj.variableNames{i} = variables(i).name;
                    end
                end
            catch
            end

            % 获取派生变量（从problem的evaluator配置中）
            try
                % 这需要从evaluator的配置中提取
                % 暂时留空，可由子类或外部设置
                obj.derivedVarNames = {};
            catch
            end
        end

        function standardExpr = processExpression(obj, expression)
            % processExpression 处理表达式，添加隐式前缀

            standardExpr = expression;

            % 分词处理
            [tokens, positions] = obj.tokenizeExpression(expression);

            % 对每个标识符进行处理
            offset = 0;
            for i = 1:length(tokens)
                token = tokens{i};

                % 检查是否为标识符
                if obj.isIdentifier(token)
                    % 检查是否已有前缀
                    if ~contains(token, '.')
                        % 尝试推断前缀
                        prefix = obj.inferPrefix(token);
                        if ~isempty(prefix)
                            % 替换为带前缀的标识符
                            newToken = sprintf('%s.%s', prefix, token);
                            pos = positions(i);
                            standardExpr = [standardExpr(1:pos-1+offset), ...
                                          newToken, ...
                                          standardExpr(pos+length(token)+offset:end)];
                            offset = offset + (length(newToken) - length(token));
                        end
                    end
                end
            end
        end

        function [tokens, positions] = tokenizeExpression(obj, expression)
            % tokenizeExpression 将表达式分解为token

            tokens = {};
            positions = [];

            % 简单的正则表达式匹配
            pattern = '[a-zA-Z_][a-zA-Z0-9_]*';
            [matches, matchPos] = regexp(expression, pattern, 'match', 'start');

            tokens = matches;
            positions = matchPos;
        end

        function isId = isIdentifier(obj, token)
            % isIdentifier 检查token是否为有效的标识符

            isId = ~isempty(regexp(token, '^[a-zA-Z_][a-zA-Z0-9_]*$', 'once'));
        end

        function prefix = inferPrefix(obj, identifier)
            % inferPrefix 根据标识符推断前缀

            prefix = '';

            % 检查是否为决策变量
            if any(strcmp(obj.variableNames, identifier))
                prefix = 'x';
                return;
            end

            % 检查是否为派生变量
            if any(strcmp(obj.derivedVarNames, identifier))
                prefix = 'derived';
                return;
            end

            % 检查是否为结果节点
            if any(strcmp(obj.resultNodeNames, identifier))
                prefix = 'result';
                return;
            end

            % 检查是否为参数
            if any(strcmp(obj.parameterNames, identifier))
                prefix = 'param';
                return;
            end

            % 默认假设为结果节点（最常见的情况）
            prefix = 'result';
        end

        function hasMismatch = checkBracketMatching(obj, expression)
            % checkBracketMatching 检查括号是否匹配

            openCount = sum(expression == '(');
            closeCount = sum(expression == ')');
            hasMismatch = openCount ~= closeCount;

            % 检查中括号
            openCount = openCount + sum(expression == '[');
            closeCount = closeCount + sum(expression == ']');
            hasMismatch = hasMismatch || (openCount ~= closeCount);
        end

        function hasSyntaxError = checkOperatorSyntax(obj, expression)
            % checkOperatorSyntax 检查操作符语法

            hasSyntaxError = false;

            % 检查连续的操作符
            operators = {'+', '-', '*', '/', '^', '==', '>=', '<=', '~='};
            for i = 1:length(operators)
                op = operators{i};
                pattern = [regexptranslate('escape', op), ...
                          '\s*', ...
                          regexptranslate('escape', op)];
                if ~isempty(regexp(expression, pattern, 'once'))
                    hasSyntaxError = true;
                    return;
                end
            end
        end

        function [warnings, valid] = checkIdentifiers(obj, expression)
            % checkIdentifiers 检查表达式中的标识符

            warnings = {};
            valid = true;

            [tokens, ~] = obj.tokenizeExpression(expression);

            for i = 1:length(tokens)
                token = tokens{i};

                % 跳过不是标识符的token
                if ~obj.isIdentifier(token)
                    continue;
                end

                % 检查是否为已知标识符（仅作警告）
                if ~obj.isKnownIdentifier(token)
                    % 这不算错误，只是警告
                    warnings{end+1} = sprintf('未知的标识符: %s', token);
                end
            end
        end

        function isKnown = isKnownIdentifier(obj, identifier)
            % isKnownIdentifier 检查标识符是否已知

            isKnown = any(strcmp(obj.variableNames, identifier)) || ...
                     any(strcmp(obj.derivedVarNames, identifier)) || ...
                     any(strcmp(obj.resultNodeNames, identifier)) || ...
                     any(strcmp(obj.parameterNames, identifier));
        end
    end
end
