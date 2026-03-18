%% quickstart - MAPO 最小入门示例
% 用 ZDT1 测试函数 + NSGA-II 跑一个 5 变量、20 种群、10 代的多目标优化。
% 零外部依赖（不需要 Aspen Plus），约 30 秒内完成。
%
% 用法:
%   quickstart          % 直接在命令行运行
%   results = quickstart % 获取返回结果
%
% 说明:
%   本脚本演示 MAPO 框架的核心 API：
%   1. 用 Variable / Objective 定义优化问题
%   2. 用 ZDT1Evaluator 作为评估器（纯数学函数，无需仿真器）
%   3. 用 AlgorithmFactory 创建 NSGA-II 算法并运行
%
% 完成后会输出 Pareto 前沿并提示下一步操作。

function results = quickstart()
    %% 添加框架路径
    projectRoot = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(projectRoot, 'framework')));

    fprintf('========================================\n');
    fprintf('MAPO Quickstart - ZDT1 + NSGA-II\n');
    fprintf('========================================\n\n');

    %% 定义优化问题（5 个连续变量，2 个最小化目标）
    problem = OptimizationProblem('ZDT1_Quickstart', 'ZDT1 multi-objective test');
    for i = 1:5
        problem.addVariable(Variable(sprintf('x%d', i), 'continuous', [0, 1]));
    end
    problem.addObjective(Objective('f1', 'minimize'));
    problem.addObjective(Objective('f2', 'minimize'));

    %% 设置评估器
    evaluator = ZDT1Evaluator();
    problem.setEvaluator(evaluator);
    try evaluator.setProblem(problem); catch; end

    %% 创建算法并运行
    algorithm = AlgorithmFactory.create('NSGA-II');

    params = struct();
    params.populationSize = 20;
    params.maxGenerations = 10;
    params.crossoverRate = 0.9;
    params.mutationRate = 1.0;
    params.crossoverDistIndex = 20;
    params.mutationDistIndex = 20;

    fprintf('变量数: 5 | 种群: 20 | 代数: 10\n');
    fprintf('开始优化...\n\n');

    results = algorithm.optimize(problem, params);

    %% 输出结果
    fprintf('\n========================================\n');
    fprintf('优化完成\n');
    fprintf('========================================\n');
    fprintf('  评估次数: %d\n', results.evaluations);
    fprintf('  运行代数: %d\n', results.iterations);
    fprintf('  耗时: %.2f 秒\n', results.elapsedTime);

    if isfield(results, 'paretoFront') && ~isempty(results.paretoFront)
        fprintf('  Pareto 解数: %d\n', results.paretoFront.size());
    end

    %% 下一步
    fprintf('\n--- 下一步 ---\n');
    fprintf('1. 启动 GUI:          launchGUI()\n');
    fprintf('2. 使用模板配置:      edit(''example/_template/case_config.json'')\n');
    fprintf('3. 查看最小配置示例:  edit(''example/_template/case_config_minimal.json'')\n');
    fprintf('4. 运行冒烟测试:      run_smoke_algorithm(''all'')\n');
    fprintf('5. 查看实际案例:      cd(''example/ADN''); edit(''case_config.json'')\n');
    fprintf('========================================\n');
end
