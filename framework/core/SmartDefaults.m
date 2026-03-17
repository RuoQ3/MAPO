classdef SmartDefaults < handle
    % SmartDefaults 智能默认值推荐
    %
    % 功能:
    %   - 根据问题特征分析推荐合适的算法
    %   - 推荐算法参数
    %   - 推荐评估器配置
    %   - 启发式规则库管理
    %
    % 示例:
    %   defaults = SmartDefaults();
    %   algo = defaults.recommendAlgorithm(problem);
    %   params = defaults.recommendParameters('NSGA-II', problem);

    properties (Access = private)
        rules              % 推荐规则库
    end

    methods
        function obj = SmartDefaults()
            % SmartDefaults 构造函数

            obj.initializeRules();
        end

        function algorithm = recommendAlgorithm(obj, problem)
            % recommendAlgorithm 根据问题特征推荐算法
            %
            % 输入:
            %   problem - OptimizationProblem对象
            %
            % 输出:
            %   algorithm - 推荐的算法类型 ('NSGA-II', 'PSO', 'ANN-NSGA-II')
            %
            % 说明:
            %   基于变量数、目标数、约束数等特征进行推荐

            if isempty(problem)
                algorithm = 'NSGA-II';  % 默认算法
                return;
            end

            nVars = problem.getNumberOfVariables();
            nObjs = problem.getNumberOfObjectives();
            nCons = problem.getNumberOfConstraints();

            % 推荐逻辑
            if nVars > 20 && nObjs > 3
                % 高维多目标问题 -> 推荐ANN-NSGA-II
                algorithm = 'ANN-NSGA-II';
            elseif nObjs > 1
                % 多目标 -> 推荐NSGA-II
                algorithm = 'NSGA-II';
            else
                % 单目标 -> 推荐PSO
                algorithm = 'PSO';
            end
        end

        function params = recommendParameters(obj, algorithm, problem)
            % recommendParameters 推荐算法参数
            %
            % 输入:
            %   algorithm - 算法类型
            %   problem - OptimizationProblem对象
            %
            % 输出:
            %   params - 推荐的参数struct

            params = struct();

            if isempty(problem)
                nVars = 10;
                nObjs = 2;
            else
                nVars = problem.getNumberOfVariables();
                nObjs = problem.getNumberOfObjectives();
            end

            switch algorithm
                case 'NSGA-II'
                    params = obj.recommendNSGAIIParams(nVars, nObjs);

                case 'PSO'
                    params = obj.recommendPSOParams(nVars, nObjs);

                case 'ANN-NSGA-II'
                    params = obj.recommendANNNSGAIIParams(nVars, nObjs);

                otherwise
                    params.populationSize = 100;
                    params.maxGenerations = 250;
            end
        end

        function evaluator_cfg = recommendEvaluator(obj, problem)
            % recommendEvaluator 推荐评估器配置
            %
            % 输入:
            %   problem - OptimizationProblem对象
            %
            % 输出:
            %   evaluator_cfg - 推荐的评估器配置

            evaluator_cfg = struct();
            evaluator_cfg.type = 'ExpressionEvaluator';  % 默认推荐ExpressionEvaluator
            evaluator_cfg.timeout = 300;  % 默认超时5分钟

            % 根据问题特征调整
            if ~isempty(problem)
                nVars = problem.getNumberOfVariables();
                nObjs = problem.getNumberOfObjectives();

                if nVars > 50 || nObjs > 10
                    % 复杂问题增加超时时间
                    evaluator_cfg.timeout = 600;
                else
                    evaluator_cfg.timeout = 300;
                end
            end
        end

        function summary = summarizeRecommendations(obj, problem)
            % summarizeRecommendations 生成推荐总结
            %
            % 输入:
            %   problem - OptimizationProblem对象
            %
            % 输出:
            %   summary - 推荐总结struct

            summary = struct();

            nVars = problem.getNumberOfVariables();
            nObjs = problem.getNumberOfObjectives();
            nCons = problem.getNumberOfConstraints();

            % 问题特征分析
            summary.problemCharacteristics = sprintf( ...
                '问题维度: %d变量, %d目标, %d约束', nVars, nObjs, nCons);

            if nVars <= 5
                complexity = '低维';
            elseif nVars <= 20
                complexity = '中维';
            else
                complexity = '高维';
            end

            summary.complexity = complexity;

            % 推荐算法
            algorithm = obj.recommendAlgorithm(problem);
            summary.recommendedAlgorithm = algorithm;

            % 推荐参数
            params = obj.recommendParameters(algorithm, problem);
            summary.parameters = params;

            % 估计运行时间（基本估计）
            switch algorithm
                case 'NSGA-II'
                    nEvals = params.populationSize * (params.maxGenerations + 1);
                case 'PSO'
                    nEvals = params.swarmSize * params.maxIterations;
                case 'ANN-NSGA-II'
                    nEvals = params.trainingSamples + params.populationSize * (params.maxGenerations + 1);
                otherwise
                    nEvals = 10000;
            end

            summary.estimatedEvaluations = nEvals;
            summary.estimatedRunTime = sprintf('约%d个评估', nEvals);

            % 建议
            suggestions = {};
            if nVars > 30
                suggestions{end+1} = '变量数较多，建议使用ANN辅助代理模型';
            end
            if nObjs > 5
                suggestions{end+1} = '目标数较多，建议增加种群大小';
            end
            if nCons > 5
                suggestions{end+1} = '约束数较多，建议注意可行解搜索';
            end

            summary.suggestions = suggestions;
        end
    end

    methods (Access = private)
        function initializeRules(obj)
            % initializeRules 初始化推荐规则库

            % 规则库包含各种启发式规则
            obj.rules = struct();

            % NSGA-II推荐规则
            obj.rules.nsga2 = struct();
            obj.rules.nsga2.minPopSize = 50;
            obj.rules.nsga2.maxPopSize = 300;
            obj.rules.nsga2.minGenerations = 100;
            obj.rules.nsga2.maxGenerations = 500;

            % PSO推荐规则
            obj.rules.pso = struct();
            obj.rules.pso.minSwarmSize = 20;
            obj.rules.pso.maxSwarmSize = 100;
            obj.rules.pso.minIterations = 100;
            obj.rules.pso.maxIterations = 500;

            % ANN-NSGA-II推荐规则
            obj.rules.ann_nsga2 = struct();
            obj.rules.ann_nsga2.minTrainingSamples = 100;
            obj.rules.ann_nsga2.maxTrainingSamples = 500;
        end

        function params = recommendNSGAIIParams(obj, nVars, nObjs)
            % recommendNSGAIIParams NSGA-II参数推荐

            params = struct();

            % 种群大小：基于变量数
            if nVars <= 5
                params.populationSize = 50;
            elseif nVars <= 20
                params.populationSize = 100;
            else
                params.populationSize = 150;
            end

            % 代数：基于问题复杂度
            params.maxGenerations = min(500, max(100, 250 * (1 + nObjs/2)));

            % 交叉率和变异率（标准设置）
            params.crossoverRate = 0.9;
            params.mutationRate = 1 / nVars;

            % 分布指数
            params.crossoverDistIndex = 20;
            params.mutationDistIndex = 20;
        end

        function params = recommendPSOParams(obj, nVars, ~)
            % recommendPSOParams PSO参数推荐

            params = struct();

            % 种群大小
            if nVars <= 5
                params.swarmSize = 20;
            else
                params.swarmSize = max(20, min(100, 10 + 2*nVars));
            end

            % 迭代数
            params.maxIterations = 250;

            % 加速度常数
            params.w = 0.7298;
            params.c1 = 1.49618;
            params.c2 = 1.49618;

            % 速度限制
            params.vMax = 0.2;
        end

        function params = recommendANNNSGAIIParams(obj, nVars, nObjs)
            % recommendANNNSGAIIParams ANN-NSGA-II参数推荐

            params = struct();

            % 基础NSGA-II参数
            base_params = obj.recommendNSGAIIParams(nVars, nObjs);
            params.populationSize = base_params.populationSize;
            params.maxGenerations = base_params.maxGenerations;
            params.crossoverDistIndex = base_params.crossoverDistIndex;
            params.mutationDistIndex = base_params.mutationDistIndex;

            % 训练数据采样
            if nVars <= 10
                params.trainingSamples = 100;
            elseif nVars <= 30
                params.trainingSamples = 200;
            else
                params.trainingSamples = 300;
            end

            % 代理模型类型
            if nVars <= 15
                params.surrogateType = 'poly2';  % 二阶多项式
            else
                params.surrogateType = 'ann';    % 人工神经网络
            end
        end
    end
end
