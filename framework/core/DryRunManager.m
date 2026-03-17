classdef DryRunManager < handle
    % DryRunManager 试算运行管理器
    %
    % 功能:
    %   - 支持快速试算（不需要完整的优化配置）
    %   - 缓存仿真结果
    %   - 检测并报告仿真失败
    %   - 提供简洁的接口用于GUI预览
    %
    % 示例:
    %   manager = DryRunManager();
    %   [objectives, constraints, success] = manager.runDryRun([1.5, 2.3, 3.1], evaluator);

    properties (Access = private)
        lastResult          % 缓存的上一次结果
        lastVariables       % 缓存的上一次变量值
        errorLog            % 错误日志
        resultHistory       % 结果历史记录
        maxHistorySize = 100;  % 最大历史记录条数
    end

    methods
        function obj = DryRunManager()
            % DryRunManager 构造函数
            obj.lastResult = [];
            obj.lastVariables = [];
            obj.errorLog = {};
            obj.resultHistory = {};
        end

        function [objectives, constraints, success, message] = runDryRun(obj, variableValues, evaluator)
            % runDryRun 执行一次试算
            %
            % 输入:
            %   variableValues - 变量值向量 [1×n]
            %   evaluator - Evaluator对象
            %
            % 输出:
            %   objectives - 目标值向量或标量
            %   constraints - 约束值向量（如果有约束）
            %   success - 布尔值，仿真是否成功
            %   message - 错误信息（如果success=false）
            %
            % 示例:
            %   [obj, constr, ok, msg] = manager.runDryRun([1.5, 2.3], evaluator);

            if nargin < 3
                error('DryRunManager:InsufficientArgs', '需要提供variableValues和evaluator参数');
            end

            if isempty(evaluator)
                error('DryRunManager:EmptyEvaluator', 'Evaluator不能为空');
            end

            % 初始化返回值
            objectives = [];
            constraints = [];
            success = false;
            message = '';

            try
                % 执行评估
                result = evaluator.evaluate(variableValues);

                % 检查评估结果
                if ~isstruct(result)
                    throw(MException('DryRunManager:InvalidResult', ...
                        '评估器返回非struct结果'));
                end

                % 提取目标值
                if isfield(result, 'objectives') && ~isempty(result.objectives)
                    objectives = result.objectives;
                else
                    throw(MException('DryRunManager:NoObjectives', ...
                        '评估结果中缺少objectives字段'));
                end

                % 提取约束值（可选）
                if isfield(result, 'constraints') && ~isempty(result.constraints)
                    constraints = result.constraints;
                else
                    constraints = [];
                end

                % 检查success标志
                if isfield(result, 'success')
                    success = result.success;
                else
                    success = true;  % 默认认为成功
                end

                if ~success && isfield(result, 'errorMessage')
                    message = result.errorMessage;
                end

            catch ME
                % 捕获错误
                success = false;
                message = sprintf('试算失败: %s (%s)', ME.message, ME.identifier);
                obj.errorLog{end+1} = struct('timestamp', datetime('now'), ...
                                            'variables', variableValues, ...
                                            'error', message);
            end

            % 缓存结果
            obj.lastResult = struct('objectives', objectives, ...
                                    'constraints', constraints, ...
                                    'success', success);
            obj.lastVariables = variableValues;

            % 记录到历史
            obj.recordToHistory(variableValues, objectives, constraints, success);
        end

        function result = getLastResult(obj)
            % getLastResult 获取上一次的试算结果
            %
            % 输出:
            %   result - 上一次的结果结构体（如果没有缓存则为空）
            %
            % 示例:
            %   result = manager.getLastResult();

            result = obj.lastResult;
        end

        function variables = getLastVariables(obj)
            % getLastVariables 获取上一次的变量值
            %
            % 输出:
            %   variables - 上一次使用的变量值

            variables = obj.lastVariables;
        end

        function clearCache(obj)
            % clearCache 清除缓存的结果
            %
            % 说明:
            %   清除最后一次的结果和变量缓存

            obj.lastResult = [];
            obj.lastVariables = [];
        end

        function log = getErrorLog(obj)
            % getErrorLog 获取错误日志
            %
            % 输出:
            %   log - 错误日志cell数组

            log = obj.errorLog;
        end

        function clearErrorLog(obj)
            % clearErrorLog 清除错误日志

            obj.errorLog = {};
        end

        function history = getHistory(obj)
            % getHistory 获取结果历史记录
            %
            % 输出:
            %   history - 历史记录cell数组

            history = obj.resultHistory;
        end

        function clearHistory(obj)
            % clearHistory 清除历史记录

            obj.resultHistory = {};
        end

        function stats = getStatistics(obj)
            % getStatistics 获取试算统计信息
            %
            % 输出:
            %   stats - 包含统计信息的结构体
            %   - totalRuns: 总试算次数
            %   - successRuns: 成功试算次数
            %   - failureRuns: 失败试算次数
            %   - successRate: 成功率

            stats = struct();
            stats.totalRuns = length(obj.resultHistory);
            stats.successRuns = sum([obj.resultHistory{:}.success]);
            stats.failureRuns = stats.totalRuns - stats.successRuns;

            if stats.totalRuns > 0
                stats.successRate = stats.successRuns / stats.totalRuns;
            else
                stats.successRate = 0;
            end

            stats.errorCount = length(obj.errorLog);
        end
    end

    methods (Access = private)
        function recordToHistory(obj, variables, objectives, constraints, success)
            % recordToHistory 记录结果到历史
            %
            % 内部方法，用于维护历史记录

            entry = struct();
            entry.timestamp = datetime('now');
            entry.variables = variables;
            entry.objectives = objectives;
            entry.constraints = constraints;
            entry.success = success;

            obj.resultHistory{end+1} = entry;

            % 保持历史大小在限制以内
            if length(obj.resultHistory) > obj.maxHistorySize
                obj.resultHistory(1) = [];
            end
        end
    end
end
