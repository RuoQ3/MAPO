classdef TimeBudgetEstimator < handle
    % TimeBudgetEstimator 时间预算估算器
    %
    % 功能:
    %   - 记录仿真耗时
    %   - 基于历史数据预估总运行时间
    %   - 进度预测和剩余时间计算
    %   - 时间限制管理
    %
    % 示例:
    %   estimator = TimeBudgetEstimator();
    %   estimator.recordSimulationTime(15.5);
    %   totalTime = estimator.estimateTotalTime('NSGA-II', problem);

    properties (Access = private)
        simulationTimes    % 仿真耗时记录 (秒)
        algorithmProfile   % 不同算法的时间特征
        timeBudget         % 时间预算限制 (秒)
        startTime          % 优化开始时间
        evaluationHistory  % 评估时间历史
        overheadFraction   % 开销占比（初值化、排序等）
    end

    methods
        function obj = TimeBudgetEstimator()
            % TimeBudgetEstimator 构造函数

            obj.simulationTimes = [];
            obj.algorithmProfile = struct();
            obj.timeBudget = Inf;  % 默认无限制
            obj.startTime = [];
            obj.evaluationHistory = {};
            obj.overheadFraction = 0.15;  % 假设15%的开销
        end

        function recordSimulationTime(obj, duration)
            % recordSimulationTime 记录单次仿真耗时
            %
            % 输入:
            %   duration - 耗时（秒）

            obj.simulationTimes(end+1) = duration;
        end

        function avgTime = getAverageSimulationTime(obj)
            % getAverageSimulationTime 获取平均仿真耗时

            if isempty(obj.simulationTimes)
                avgTime = [];
                return;
            end

            avgTime = mean(obj.simulationTimes);
        end

        function maxTime = getMaxSimulationTime(obj)
            % getMaxSimulationTime 获取最长仿真耗时

            if isempty(obj.simulationTimes)
                maxTime = [];
                return;
            end

            maxTime = max(obj.simulationTimes);
        end

        function minTime = getMinSimulationTime(obj)
            % getMinSimulationTime 获取最短仿真耗时

            if isempty(obj.simulationTimes)
                minTime = [];
                return;
            end

            minTime = min(obj.simulationTimes);
        end

        function estimate = estimateTotalTime(obj, algorithm, problem)
            % estimateTotalTime 估算优化的总运行时间
            %
            % 输入:
            %   algorithm - 算法类型 ('NSGA-II', 'PSO', 'ANN-NSGA-II')
            %   problem - OptimizationProblem对象
            %
            % 输出:
            %   estimate - 估算的运行时间（秒）

            estimate = struct();

            if isempty(obj.simulationTimes)
                estimate.totalSeconds = NaN;
                estimate.totalHours = NaN;
                estimate.estimationReliability = 0;
                estimate.message = '缺少仿真耗时数据，无法估算';
                return;
            end

            % 获取算法参数
            switch algorithm
                case 'NSGA-II'
                    % 默认参数
                    popSize = 100;
                    nGen = 250;
                    nEvals = popSize * (nGen + 1);

                case 'PSO'
                    popSize = 30;
                    maxIter = 250;
                    nEvals = popSize * maxIter;

                case 'ANN-NSGA-II'
                    % ANN版本包括训练阶段
                    trainSamples = 200;
                    popSize = 100;
                    nGen = 250;
                    nEvals = trainSamples + popSize * (nGen + 1);

                otherwise
                    nEvals = 1000;  % 默认估计
            end

            % 计算总耗时 = 评估数 * 平均仿真时间 * (1 + 开销占比)
            avgSimTime = mean(obj.simulationTimes);
            totalWithOverhead = nEvals * avgSimTime * (1 + obj.overheadFraction);

            estimate.nEvaluations = nEvals;
            estimate.avgSimulationTime = avgSimTime;
            estimate.totalSeconds = totalWithOverhead;
            estimate.totalHours = totalWithOverhead / 3600;
            estimate.totalMinutes = totalWithOverhead / 60;

            % 估计可信度（基于样本数）
            nSamples = length(obj.simulationTimes);
            estimate.estimationReliability = min(1, nSamples / 30);  % 30个样本为最高可信度

            % 生成友好的文本信息
            if totalWithOverhead < 60
                estimate.message = sprintf('预计运行时间: %.1f秒', totalWithOverhead);
            elseif totalWithOverhead < 3600
                estimate.message = sprintf('预计运行时间: %.1f分钟', totalWithOverhead/60);
            else
                estimate.message = sprintf('预计运行时间: %.1f小时', totalWithOverhead/3600);
            end

            estimate.message = sprintf('%s (基于%d个仿真样本，可信度: %.0f%%)', ...
                estimate.message, nSamples, estimate.estimationReliability * 100);
        end

        function remaining = estimateRemainingTime(obj, currentEval, totalEvals)
            % estimateRemainingTime 估算剩余时间
            %
            % 输入:
            %   currentEval - 已完成的评估数
            %   totalEvals - 总评估数
            %
            % 输出:
            %   remaining - 剩余时间（秒）

            if isempty(obj.startTime)
                remaining = NaN;
                return;
            end

            elapsedTime = toc(obj.startTime);

            if currentEval <= 0
                remaining = NaN;
                return;
            end

            % 平均每个评估的耗时
            timePerEval = elapsedTime / currentEval;

            % 剩余评估数
            remainingEvals = totalEvals - currentEval;

            % 剩余时间
            remaining = timePerEval * remainingEvals;
        end

        function setTimeBudget(obj, seconds)
            % setTimeBudget 设置时间预算限制
            %
            % 输入:
            %   seconds - 时间限制（秒）

            if seconds <= 0
                warning('TimeBudgetEstimator:InvalidBudget', '时间预算必须大于0');
                return;
            end

            obj.timeBudget = seconds;
        end

        function budget = getTimeBudget(obj)
            % getTimeBudget 获取时间预算限制

            budget = obj.timeBudget;
        end

        function startOptimization(obj)
            % startOptimization 标记优化开始

            obj.startTime = tic;
        end

        function [isExpired, remaining] = checkTimeBudget(obj)
            % checkTimeBudget 检查时间预算是否已超限
            %
            % 输出:
            %   isExpired - 布尔值，是否超限
            %   remaining - 剩余时间（秒）

            if isempty(obj.startTime) || isinf(obj.timeBudget)
                isExpired = false;
                remaining = Inf;
                return;
            end

            elapsedTime = toc(obj.startTime);
            remaining = obj.timeBudget - elapsedTime;

            isExpired = remaining <= 0;
        end

        function progress = getOptimizationProgress(obj, currentEval, totalEvals)
            % getOptimizationProgress 获取当前进度信息
            %
            % 输入:
            %   currentEval - 已完成的评估数
            %   totalEvals - 总评估数
            %
            % 输出:
            %   progress - 进度struct

            progress = struct();
            progress.completedEvaluations = currentEval;
            progress.totalEvaluations = totalEvals;

            if totalEvals > 0
                progress.completionPercentage = (currentEval / totalEvals) * 100;
            else
                progress.completionPercentage = 0;
            end

            if ~isempty(obj.startTime)
                progress.elapsedTime = toc(obj.startTime);
            else
                progress.elapsedTime = 0;
            end

            remaining = obj.estimateRemainingTime(currentEval, totalEvals);
            if ~isnan(remaining)
                progress.estimatedRemaining = remaining;
                progress.estimatedCompletion = datetime('now') + seconds(remaining);
            else
                progress.estimatedRemaining = NaN;
                progress.estimatedCompletion = NaT;
            end

            % 生成进度条字符串
            barLength = 50;
            filledLength = round(progress.completionPercentage / 100 * barLength);
            emptyLength = barLength - filledLength;

            progress.progressBar = sprintf('[%s%s] %.1f%%', ...
                repmat('=', 1, filledLength), ...
                repmat('-', 1, emptyLength), ...
                progress.completionPercentage);
        end

        function stats = getStatistics(obj)
            % getStatistics 获取仿真时间统计信息

            stats = struct();

            if isempty(obj.simulationTimes)
                stats.count = 0;
                stats.mean = NaN;
                stats.median = NaN;
                stats.std = NaN;
                stats.min = NaN;
                stats.max = NaN;
                stats.total = NaN;
                return;
            end

            stats.count = length(obj.simulationTimes);
            stats.mean = mean(obj.simulationTimes);
            stats.median = median(obj.simulationTimes);
            stats.std = std(obj.simulationTimes);
            stats.min = min(obj.simulationTimes);
            stats.max = max(obj.simulationTimes);
            stats.total = sum(obj.simulationTimes);
        end

        function clear(obj)
            % clear 清除所有记录

            obj.simulationTimes = [];
            obj.startTime = [];
            obj.evaluationHistory = {};
        end
    end
end
