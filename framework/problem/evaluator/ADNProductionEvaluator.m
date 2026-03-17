classdef ADNProductionEvaluator < Evaluator
    % ADNProductionEvaluator ADN生产工艺评估器
    % Evaluator for ADN Production Process Optimization
    %
    % 功能:
    %   - 继承 Evaluator 抽象类，规范化处理目标函数
    %   - 调用Aspen Plus仿真器进行二级氢氰化工段仿真
    %   - 计算ADN质量分数和ADN质量流量
    %   - 根据 OptimizationProblem 中的 Objective 类型自动处理最大化/最小化
    %
    % 优化目标（在 OptimizationProblem 中定义）:
    %   1. ADN质量分数（添加为 maximize 或 minimize）
    %   2. ADN质量流量（添加为 maximize 或 minimize）
    %
    % 设计变量:
    %   1. T0301_BF - 塔底采出比 [0.3, 0.9]
    %   2. T0301_FEED_STAGE - 进料板位置 [10, 20]
    %   3. T0301_BASIS_RR - 回流比 [1, 3]
    %
    % 使用示例:
    %   % 创建问题
    %   problem = OptimizationProblem('ADNProduction');
    %   problem.addVariable(Variable('T0301_BF', 'continuous', [0.3, 0.9]));
    %   problem.addVariable(Variable('T0301_FEED_STAGE', 'integer', [10, 20]));
    %   problem.addVariable(Variable('T0301_BASIS_RR', 'continuous', [1, 3]));
    %   problem.addObjective(Objective('ADN_FRAC', 'maximize'));
    %   problem.addObjective(Objective('ADN_FLOW', 'maximize'));
    %
    %   % 创建评估器
    %   simulator = AspenPlusSimulator();
    %   simulator.connect(config);
    %   evaluator = ADNProductionEvaluator(simulator);
    %   evaluator.setProblem(problem);
    %
    %   % 评估
    %   result = evaluator.evaluate([0.6, 15, 2.0]);

    properties (Access = private)
        simulator;          % AspenPlusSimulator对象
        logger;             % Logger对象
    end

    properties (Access = public)
        % 惩罚系数
        constraintPenalty;  % 约束违反惩罚（用于收敛失败）
        timeout;            % 仿真超时时间（秒）
    end

    methods
        function obj = ADNProductionEvaluator(simulator)
            % ADNProductionEvaluator 构造函数
            %
            % 输入:
            %   simulator - AspenPlusSimulator对象
            %
            % 示例:
            %   evaluator = ADNProductionEvaluator(simulator);

            % 调用父类构造函数
            obj@Evaluator();

            obj.simulator = simulator;

            % 惩罚系数（收敛失败时返回大的正值，因为是最小化问题）
            obj.constraintPenalty = 1e8;

            % 默认超时时间
            obj.timeout = 300;  % 5分钟

            % 创建logger
            if exist('Logger', 'class')
                obj.logger = Logger.getLogger('ADNProductionEvaluator');
            else
                obj.logger = [];
            end
        end

        function result = evaluate(obj, x)
            % evaluate 评估给定设计的目标函数值
            % 根据 OptimizationProblem 中的 Objective 类型自动处理最大化/最小化
            %
            % 关键特性：
            %   - 用户定义什么语义（maximize/minimize），系统就按语义执行
            %   - 不强制用户必须写 maximize 或 minimize
            %   - 内部统一转为最小化形式给算法
            %
            % 输入:
            %   x - 设计变量向量 [T0301_BF, T0301_FEED_STAGE, T0301_BASIS_RR]
            %
            % 输出:
            %   result - 评估结果结构体

            obj.evaluationCounter = obj.evaluationCounter + 1;

            % 提取设计变量
            T0301_BF = x(1);
            T0301_FEED_STAGE = round(x(2));  % 进料板位置必须是整数
            T0301_BASIS_RR = x(3);

            obj.logInfo(sprintf('评估 #%d: BF=%.4f, FEED_STAGE=%d, BASIS_RR=%.4f', ...
                obj.evaluationCounter, T0301_BF, T0301_FEED_STAGE, T0301_BASIS_RR));

            try
                % 步骤1: 运行Aspen Plus仿真
                vars = struct();
                vars.T0301_BF = T0301_BF;
                vars.T0301_FEED_STAGE = T0301_FEED_STAGE;
                vars.T0301_BASIS_RR = T0301_BASIS_RR;
                simResults = obj.runSimulation(vars);

                if ~simResults.success
                    obj.logWarning('仿真失败或收敛失败，返回错误结果');
                    result = obj.createErrorResult('仿真失败');
                    return;
                end

                % 步骤2: 提取原始结果值（物理意义上的真实值）
                ADN_FRAC = simResults.ADN_FRAC;  % ADN质量分数
                ADN_FLOW = simResults.ADN_FLOW;  % ADN质量流量

                % 步骤3: 根据用户定义的目标类型进行处理
                % 关键原则：用户写什么语义，系统就按什么语义执行
                %   - 如果用户定义 maximize，说明想要更大的值 -> 取负（最小化-value）
                %   - 如果用户定义 minimize，说明想要更小的值 -> 直接用（最小化value）
                %   - 如果用户没定义type，默认 minimize
                objectives = [];
                nObjs = obj.problem.getNumberOfObjectives();

                for i = 1:nObjs
                    objective = obj.problem.getObjective(i);

                    % 根据目标名称获取对应的计算值
                    if strcmp(objective.name, 'ADN_FRAC')
                        value = ADN_FRAC;
                    elseif strcmp(objective.name, 'ADN_FLOW')
                        value = ADN_FLOW;
                    else
                        obj.logWarning(sprintf('未知的目标: %s，使用默认值0', objective.name));
                        value = 0;
                    end

                    % 根据目标语义转换
                    % 如果用户定义为 maximize（想要最大值），则取负转为最小化
                    % 如果用户定义为 minimize（想要最小值），则直接用
                    if objective.isMaximize()
                        value = -value;  % 转为最小化：最大化value = 最小化-value
                        obj.logInfo(sprintf('  目标 %s: 用户定义为 maximize，内部转为 minimize(-value)', objective.name));
                    else
                        obj.logInfo(sprintf('  目标 %s: 用户定义为 minimize，直接使用', objective.name));
                    end

                    objectives = [objectives, value];
                end

                % 步骤4: 构造成功结果
                constraints = [];  % 此评估器不返回约束
                result = obj.createSuccessResult(objectives, constraints);

                obj.logInfo(sprintf('  原始结果: ADN_FRAC=%.6f, ADN_FLOW=%.6f kg/hr', ...
                    ADN_FRAC, ADN_FLOW));
                obj.logInfo(sprintf('  处理后目标值: [%.6f, %.6f]', objectives(1), objectives(2)));

            catch ME
                obj.logError(sprintf('评估异常: %s', ME.message));
                result = obj.createErrorResult(ME.message);
            end
        end
    end

    methods (Access = private)
        function simResults = runSimulation(obj, vars)
            % runSimulation 运行Aspen Plus仿真
            %
            % 输入:
            %   vars - struct，字段为变量名
            %
            % 输出:
            %   simResults - 仿真结果结构体

            simResults = struct();
            simResults.success = false;

            try
                % 设置Aspen变量
                obj.simulator.setVariables(vars);

                % 运行仿真
                success = obj.simulator.run(obj.timeout);

                if ~success
                    obj.logWarning('Aspen仿真运行失败或收敛失败');
                    return;
                end

                % 获取结果（通过结果名称，会自动使用 resultMapping）
                results = obj.simulator.getResults({'ADN_FRAC', 'ADN_FLOW'});

                simResults.ADN_FRAC = results.ADN_FRAC;
                simResults.ADN_FLOW = results.ADN_FLOW;
                simResults.success = true;

            catch ME
                obj.logError(sprintf('仿真执行异常: %s', ME.message));
                simResults.success = false;
            end
        end

        % 日志方法
        function logInfo(obj, message)
            if ~isempty(obj.logger)
                obj.logger.info(message);
            else
                fprintf('[INFO] %s\n', message);
            end
        end

        function logWarning(obj, message)
            if ~isempty(obj.logger)
                obj.logger.warning(message);
            else
                fprintf('[WARN] %s\n', message);
            end
        end

        function logError(obj, message)
            if ~isempty(obj.logger)
                obj.logger.error(message);
            else
                fprintf('[ERROR] %s\n', message);
            end
        end
    end
end
