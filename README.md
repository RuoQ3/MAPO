# MAPO - MATLAB-Aspen Process Optimizer

[![MATLAB](https://img.shields.io/badge/MATLAB-R2020a%2B-orange)](https://www.mathworks.com/products/matlab.html)
[![Aspen Plus](https://img.shields.io/badge/Aspen%20Plus-V11%2B-blue)](https://www.aspentech.com/en/products/engineering/aspen-plus)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.1-brightgreen)](CHANGELOG.md)

MAPO 是一个集成 MATLAB 优化算法与 Aspen Plus 过程仿真的化工流程多目标优化框架。支持 NSGA-II、PSO、ANN-NSGA-II 算法，提供 JSON 配置驱动、表达式求值引擎、GUI 可视化操作与模块化插件系统。

## 目录

- [系统要求](#系统要求)
- [安装](#安装)
- [30 秒快速体验](#30-秒快速体验)
- [完整使用教程：以 ADN 生产优化为例](#完整使用教程以-adn-生产优化为例)
  - [背景说明](#背景说明)
  - [方式一：JSON 配置 + 通用脚本（推荐）](#方式一json-配置--通用脚本推荐)
  - [方式二：编程式调用（完全控制）](#方式二编程式调用完全控制)
  - [方式三：GUI 可视化操作](#方式三gui-可视化操作)
- [配置文件详解](#配置文件详解)
  - [problem 段](#problem-段)
  - [simulator 段](#simulator-段)
  - [algorithm 段](#algorithm-段)
- [算法选择指南](#算法选择指南)
- [评估器选择指南](#评估器选择指南)
- [结果输出与分析](#结果输出与分析)
- [扩展开发](#扩展开发)
- [常见问题排查](#常见问题排查)
- [项目结构](#项目结构)
- [版本历史](#版本历史)
- [许可证与联系方式](#许可证与联系方式)

---

## 系统要求

| 组件 | 要求 |
|------|------|
| MATLAB | R2020a+（推荐 R2021a+） |
| Aspen Plus | V11+（仅 Windows，COM 接口） |
| 操作系统 | Windows（Aspen COM 限制） |
| Parallel Computing Toolbox | 可选，用于并行评估 |
| Deep Learning Toolbox | 可选，ANN-NSGA-II 代理模型时需要 |

## 安装

```bash
git clone https://github.com/mapleccs/MAPO.git
cd MAPO
```

在 MATLAB 中添加路径：

```matlab
addpath(genpath('framework'));
addpath(genpath('gui'));
addpath(genpath(fullfile('example', '_template')));
```

<!-- PLACEHOLDER_QUICKSTART -->

## 30 秒快速体验

不需要 Aspen Plus，直接验证框架是否正常工作：

```matlab
quickstart
```

这会用 ZDT1 测试函数 + NSGA-II 跑一个 5 变量、2 目标的多目标优化，约 30 秒完成。

如果你想验证所有算法：

```matlab
addpath(genpath(fullfile('example', '_template')));
run_smoke_algorithm('all', 'Problem', 'zdt1', 'PopulationSize', 20, 'Iterations', 5);
```

---

## 完整使用教程：以 ADN 生产优化为例

本节以 `example/ADN/` 中的 ADN（二硝酰胺铵）生产工艺优化为完整示例，演示从配置到运行到结果分析的全流程。

### 背景说明

ADN 生产工艺中，二级氢氰化工段的精馏塔 T0301 有三个关键操作参数：

| 变量 | 含义 | 范围 | 类型 |
|------|------|------|------|
| `T0301_BF` | 塔底采出比 | [0.3, 0.9] | 连续 |
| `T0301_FEED_STAGE` | 进料板位置 | [10, 20] | 整数 |
| `T0301_BASIS_RR` | 回流比 | [1, 3] | 连续 |

优化目标是同时最大化 ADN 质量分数和 ADN 质量流量（双目标冲突，需要 Pareto 前沿）。

Aspen Plus 模型文件为 `二级氢氰化工段.bkp`，通过 COM 接口与 MATLAB 通信。

---

### 方式一：JSON 配置 + 通用脚本（推荐）

这是最简洁的使用方式，只需编写一个 JSON 配置文件，然后调用通用脚本。

#### 第 1 步：编写配置文件

创建 `case_config.json`（完整示例见 `example/ADN/case_config.json`）：

```json
{
  "problem": {
    "name": "ADN_Production",
    "description": "ADN生产工艺多目标优化",
    "variables": [
      {
        "name": "T0301_BF",
        "description": "塔底采出比",
        "type": "continuous",
        "lowerBound": 0.3,
        "upperBound": 0.9,
        "unit": "-",
        "initialValue": 0.6
      },
      {
        "name": "T0301_FEED_STAGE",
        "description": "进料板位置",
        "type": "integer",
        "lowerBound": 10,
        "upperBound": 20,
        "unit": "-",
        "initialValue": 15
      },
      {
        "name": "T0301_BASIS_RR",
        "description": "回流比",
        "type": "continuous",
        "lowerBound": 1,
        "upperBound": 3,
        "unit": "-",
        "initialValue": 2
      }
    ],
    "objectives": [
      {
        "name": "ADN_FRAC",
        "description": "ADN质量分数",
        "type": "maximize",
        "unit": "-"
      },
      {
        "name": "ADN_FLOW",
        "description": "ADN质量流量",
        "type": "maximize",
        "unit": "kg/hr"
      }
    ],
    "evaluator": {
      "type": "ADNProductionEvaluator",
      "timeout": 300
    }
  },
  "simulator": {
    "type": "Aspen",
    "settings": {
      "modelPath": "二级氢氰化工段.bkp",
      "timeout": 300,
      "visible": false,
      "maxRetries": 3,
      "retryDelay": 2
    },
    "nodeMapping": {
      "variables": {
        "T0301_BF": "\\Data\\Blocks\\T0301\\Input\\B:F",
        "T0301_FEED_STAGE": "\\Data\\Blocks\\T0301\\Input\\FEED_STAGE\\0318",
        "T0301_BASIS_RR": "\\Data\\Blocks\\T0301\\Input\\BASIS_RR"
      },
      "results": {
        "ADN_FRAC": "\\Data\\Streams\\ADN\\Output\\MASSFRAC\\MIXED\\ADN",
        "ADN_FLOW": "\\Data\\Streams\\ADN\\Output\\MASSFLOW\\MIXED\\ADN"
      }
    }
  },
  "algorithm": {
    "type": "NSGA-II",
    "parameters": {
      "populationSize": 50,
      "maxGenerations": 20,
      "crossoverRate": 0.9,
      "mutationRate": 1.0,
      "crossoverDistIndex": 20,
      "mutationDistIndex": 20
    }
  }
}
```

配置文件的三个顶层段落：
- `problem` -- 定义变量、目标、约束、评估器
- `simulator` -- 定义仿真器类型、模型路径、节点映射
- `algorithm` -- 定义算法类型和参数

#### 第 2 步：运行优化

```matlab
cd('example/ADN');
results = run_case('case_config.json');
```

`run_case` 会自动完成：配置验证 -> 创建仿真器 -> 创建评估器 -> 定义问题 -> 运行算法 -> 保存结果。

#### 第 3 步：查看结果

结果自动保存在 `results/ADN_Production_<时间戳>/` 目录下：

```
results/ADN_Production_20260318_143000/
  config.json           -- 配置备份
  pareto_front.csv      -- Pareto 前沿解（变量值 + 目标值）
  all_solutions.csv     -- 所有评估过的解
  convergence.csv       -- 收敛历史
  pareto_front.png      -- Pareto 前沿图
  optimization.log      -- 优化日志
  results.mat           -- MATLAB 数据文件
```

---

### 方式二：编程式调用（完全控制）

当你需要自定义评估逻辑、中间处理或特殊的结果分析时，使用编程式调用。

完整代码见 `example/ADN/run_adn_nsga2_optimization.m`，以下是核心流程：

```matlab
%% 1. 环境准备
addpath(genpath('framework'));
currentDir = fileparts(mfilename('fullpath'));

%% 2. 配置并连接 Aspen Plus 仿真器
simConfig = SimulatorConfig('Aspen');
simConfig.set('modelPath', fullfile(currentDir, '二级氢氰化工段.bkp'));
simConfig.set('timeout', 300);
simConfig.set('visible', false);

% 变量映射：MATLAB 变量名 -> Aspen 树节点路径
simConfig.setNodeMapping('T0301_BF', '\Data\Blocks\T0301\Input\B:F');
simConfig.setNodeMapping('T0301_FEED_STAGE', '\Data\Blocks\T0301\Input\FEED_STAGE\0318');
simConfig.setNodeMapping('T0301_BASIS_RR', '\Data\Blocks\T0301\Input\BASIS_RR');

% 结果映射：结果名 -> Aspen 树节点路径
simConfig.setResultMapping('ADN_FRAC', '\Data\Streams\ADN\Output\MASSFRAC\MIXED\ADN');
simConfig.setResultMapping('ADN_FLOW', '\Data\Streams\ADN\Output\MASSFLOW\MIXED\ADN');

simulator = AspenPlusSimulator();
simulator.connect(simConfig);

%% 3. 创建评估器
evaluator = ADNProductionEvaluator(simulator);
evaluator.timeout = 300;

%% 4. 定义优化问题
problem = OptimizationProblem('ADNProduction', 'ADN生产工艺多目标优化');

% 添加决策变量
problem.addVariable(Variable('T0301_BF', 'continuous', [0.3, 0.9]));
problem.addVariable(Variable('T0301_FEED_STAGE', 'integer', [10, 20]));
problem.addVariable(Variable('T0301_BASIS_RR', 'continuous', [1, 3]));

% 添加目标（框架自动处理 maximize -> 内部取负 -> 输出还原）
problem.addObjective(Objective('ADN_FRAC', 'maximize'));
problem.addObjective(Objective('ADN_FLOW', 'maximize'));

% 关联评估器和问题
problem.setEvaluator(evaluator);
evaluator.setProblem(problem);

%% 5. 配置并运行 NSGA-II
algoConfig = struct();
algoConfig.populationSize = 50;
algoConfig.maxGenerations = 20;
algoConfig.crossoverRate = 0.9;

nsga2 = NSGAII();
results = nsga2.optimize(problem, algoConfig);

%% 6. 提取 Pareto 前沿
paretoFront = results.paretoFront;
paretoIndividuals = paretoFront.getAll();

for i = 1:length(paretoIndividuals)
    vars = paretoIndividuals(i).getVariables();
    objs = paretoIndividuals(i).getObjectives();
    % 内部存储为最小化形式，取负还原
    fprintf('BF=%.4f, Stage=%d, RR=%.4f -> FRAC=%.6f, FLOW=%.2f\n', ...
        vars(1), round(vars(2)), vars(3), -objs(1), -objs(2));
end

%% 7. 清理
simulator.disconnect();
```

关键 API 说明：

| 类 | 用途 |
|---|---|
| `SimulatorConfig` | 配置仿真器连接参数和节点映射 |
| `AspenPlusSimulator` | 通过 COM 接口连接 Aspen Plus |
| `ADNProductionEvaluator` | ADN 专用评估器，处理仿真调用和目标计算 |
| `OptimizationProblem` | 问题容器，持有变量、目标、约束、评估器 |
| `Variable(name, type, bounds)` | 定义决策变量 |
| `Objective(name, direction)` | 定义优化目标（`'minimize'` 或 `'maximize'`） |
| `NSGAII` | NSGA-II 多目标优化算法 |
| `AlgorithmFactory.create(type)` | 通过字符串创建算法实例 |

---

### 方式三：GUI 可视化操作

```matlab
launchGUI()
```

GUI 提供 5 个标签页：

1. **问题配置** -- 定义变量、目标、约束，内置表达式验证
2. **评估器配置** -- 选择评估器类型，设置超时和经济参数
3. **仿真器配置** -- 设置 Aspen 模型路径和节点映射
4. **算法配置** -- 选择算法并调整参数
5. **运行与结果** -- 一键运行、实时监控、结果导出

操作流程：

1. 点击"加载配置"导入 `example/ADN/case_config.json`（或手动填写）
2. 在"问题配置"中确认变量和目标，点击"验证表达式"检查语法
3. 在"仿真器配置"中设置模型路径和节点映射
4. 在"算法配置"中选择 NSGA-II 并调整种群大小、代数
5. 切换到"运行与结果"，点击"开始"

---

## 配置文件详解

所有配置通过单一 JSON 文件 (`case_config.json`) 管理，包含三个顶层段。

### problem 段

```json
{
  "problem": {
    "name": "项目名称",
    "description": "项目描述",
    "variables": [...],
    "objectives": [...],
    "constraints": [...],
    "derived": [...],
    "evaluator": {
      "type": "评估器类型",
      "timeout": 300,
      "economicParameters": {}
    }
  }
}
```

#### 变量定义

支持四种类型：

| 类型 | 说明 | 必填字段 | 示例 |
|------|------|---------|------|
| `continuous` | 连续变量 | `lowerBound`, `upperBound` | 温度、压力、流量 |
| `integer` | 整数变量 | `lowerBound`, `upperBound` | 塔板数、进料位置 |
| `discrete` | 离散变量 | `lowerBound`, `upperBound` 或 `values` | 预定义的离散值集合 |
| `categorical` | 分类变量 | `values` | 工质类型、设备型号 |

```json
{
  "name": "T0301_FEED_STAGE",
  "description": "进料板位置",
  "type": "integer",
  "lowerBound": 10,
  "upperBound": 20,
  "unit": "-",
  "initialValue": 15
}
```

#### 目标定义

```json
{
  "name": "ADN_FRAC",
  "description": "ADN质量分数",
  "type": "maximize",
  "unit": "-",
  "weight": 1.0
}
```

`type` 为 `minimize` 或 `maximize`。框架内部统一按最小化处理，maximize 目标自动取负，结果输出时还原。

#### 约束定义（可选）

```json
{
  "name": "PURITY",
  "type": "inequality",
  "expression": "result.PURITY >= 0.99"
}
```

#### 派生变量定义（可选）

用于定义中间计算量，可在目标/约束表达式中通过 `derived.NAME` 引用：

```json
{
  "derived": [
    { "name": "NET_POWER", "expression": "result.W_turbine - result.W_pump" }
  ]
}
```

#### 表达式前缀

使用 `ExpressionEvaluator` 时，表达式支持以下前缀：

| 前缀 | 来源 | 示例 |
|------|------|------|
| `x.` | 决策变量 | `x.FEED_TEMP * 1.1` |
| `result.` | 仿真结果（需在 nodeMapping.results 中映射） | `result.Revenue - result.Cost` |
| `param.` | 常数参数（economicParameters 中定义） | `param.electricity_price * result.Power` |
| `derived.` | 派生变量 | `derived.NET_POWER * 8000` |

表达式引擎支持：四则运算、幂运算、比较运算、逻辑运算、内置函数（`if`, `min`, `max`, `abs`, `sqrt`, `log`, `exp`）、物理单位标注（`100[kg/hr]`）。

### simulator 段

```json
{
  "simulator": {
    "type": "Aspen",
    "settings": {
      "modelPath": "模型文件.bkp",
      "timeout": 300,
      "visible": false,
      "autoSave": false,
      "maxRetries": 3,
      "retryDelay": 2
    },
    "nodeMapping": {
      "variables": {
        "变量名": "\\Aspen\\树\\节点\\路径"
      },
      "results": {
        "结果名": "\\Aspen\\树\\节点\\路径"
      }
    }
  }
}
```

关键说明：
- `modelPath` 支持相对路径（相对于配置文件所在目录）和绝对路径
- 节点路径使用反斜杠 `\`，JSON 中需要双反斜杠 `\\` 转义
- `nodeMapping.variables` 中的键名必须与 `problem.variables` 中的 `name` 一一对应
- `nodeMapping.results` 中的键名在 `ExpressionEvaluator` 中通过 `result.键名` 引用

如何获取 Aspen 节点路径：
1. 打开 Aspen Plus 模型
2. 在 Variable Explorer 中找到目标变量
3. 右键 -> Copy Path，得到类似 `\Data\Blocks\T0301\Input\B:F` 的路径

### algorithm 段

```json
{
  "algorithm": {
    "type": "NSGA-II",
    "parameters": {
      "populationSize": 50,
      "maxGenerations": 20,
      "crossoverRate": 0.9,
      "mutationRate": 1.0,
      "crossoverDistIndex": 20,
      "mutationDistIndex": 20
    }
  }
}
```

---

## 算法选择指南

| 算法 | 适用场景 | 关键参数 | 评估次数估算 |
|------|---------|---------|-------------|
| NSGA-II | 多目标优化，通用首选 | `populationSize`, `maxGenerations` | 种群 x 代数 |
| PSO | 单目标或简单多目标 | `swarmSize`, `maxIterations` | 粒子数 x 迭代数 |
| ANN-NSGA-II | Aspen 仿真很慢时，用代理模型加速 | `training.samples`, `surrogate.type` | 训练样本数 + 验证次数 |

NSGA-II 默认参数（适合大多数化工优化问题）：

```
populationSize: 50       -- 种群大小（Aspen 仿真慢时可减小到 20-30）
maxGenerations: 20       -- 最大代数
crossoverRate: 0.9       -- 交叉概率
mutationRate: 1.0        -- 变异率（归一化，实际概率 = 1/变量数）
crossoverDistIndex: 20   -- SBX 交叉分布指数
mutationDistIndex: 20    -- 多项式变异分布指数
```

PSO 默认参数：

```
swarmSize: 30            -- 粒子群大小
maxIterations: 100       -- 最大迭代数
inertiaWeight: 0.729     -- 惯性权重
cognitiveCoeff: 1.49445  -- 认知系数
socialCoeff: 1.49445     -- 社会系数
maxVelocityRatio: 0.2    -- 最大速度比例
```

ANN-NSGA-II 参数：

```json
{
  "type": "ANN-NSGA-II",
  "parameters": {
    "populationSize": 50,
    "maxGenerations": 20,
    "training": { "samples": 100, "samplingMethod": "lhs" },
    "surrogate": { "type": "poly2" },
    "verification": { "enabled": true, "verifyTOPSIS": true }
  }
}
```

三阶段工作流：LHS 采样 -> 训练代理模型 -> 代理加速进化 -> TOPSIS 选择折中解 -> 精确验证。

---

## 评估器选择指南

| 评估器 | 适用场景 | 说明 |
|--------|---------|------|
| `ExpressionEvaluator` | 目标/约束可用数学表达式描述 | 推荐新项目使用，通过 JSON 配置表达式 |
| `ADNProductionEvaluator` | ADN 生产工艺 | 硬编码的 ADN 专用逻辑 |
| `ORCEvaluator` | ORC 余热回收系统 | 硬编码的 ORC 专用逻辑 |
| `DistillationEvaluator` | 精馏塔优化 | 硬编码的精馏专用逻辑 |
| `MyCaseEvaluator` | 自定义评估逻辑 | 用户模板，继承 Evaluator 实现 evaluate() |

对于新项目，推荐使用 `ExpressionEvaluator`，无需编写 MATLAB 代码：

```json
{
  "problem": {
    "objectives": [
      { "name": "PROFIT", "type": "maximize", "expression": "result.Revenue - result.Cost" },
      { "name": "PURITY", "type": "maximize", "expression": "result.ProductPurity" }
    ],
    "constraints": [
      { "name": "MIN_FLOW", "type": "inequality", "expression": "result.ProductFlow >= 1000" }
    ],
    "evaluator": {
      "type": "ExpressionEvaluator",
      "timeout": 300,
      "economicParameters": {
        "electricity_price": 0.06
      }
    }
  }
}
```

---

## 结果输出与分析

优化完成后，结果保存在指定目录：

```
results/<项目名>_<时间戳>/
  config.json           -- 配置备份（可复现）
  pareto_front.csv      -- Pareto 前沿解
  all_solutions.csv     -- 所有评估过的解
  convergence.csv       -- 收敛历史
  pareto_front.png      -- Pareto 前沿散点图
  optimization.log      -- 完整优化日志
  results.mat           -- MATLAB 数据（含 results 结构体）
```

在 MATLAB 中加载和分析结果：

```matlab
% 加载结果
load('results/ADN_Production_20260318/results.mat');

% 查看 Pareto 前沿
paretoFront = results.paretoFront;
fprintf('Pareto 解数量: %d\n', paretoFront.size());

% 遍历 Pareto 解
individuals = paretoFront.getAll();
for i = 1:length(individuals)
    vars = individuals(i).getVariables();
    objs = individuals(i).getObjectives();
    fprintf('解 %d: 变量=[%.4f, %d, %.4f], 目标=[%.6f, %.2f]\n', ...
        i, vars(1), round(vars(2)), vars(3), -objs(1), -objs(2));
end

% 读取 CSV 结果
T = readtable('results/ADN_Production_20260318/pareto_front.csv');
disp(T);
```

---

<!-- PLACEHOLDER_EXTEND -->

## 扩展开发

### 添加新算法

1. 在 `framework/algorithm/<name>/` 创建算法类，继承 `AlgorithmBase`：

```matlab
classdef MyAlgorithm < AlgorithmBase
    methods
        function results = optimize(obj, problem, config)
            obj.initialize(problem, config);
            while ~obj.shouldStop()
                % 生成新解 -> 评估 -> 选择/更新
            end
            results = obj.finalizeResults();
        end
    end
end
```

2. 同目录放置 `algorithm_meta.json`：

```json
{
  "type": "MY-ALG",
  "class": "MyAlgorithm",
  "displayName": "My Algorithm",
  "description": "自定义优化算法",
  "defaultParameters": { "populationSize": 50, "maxGenerations": 20 }
}
```

3. 刷新注册（或重启 GUI）：

```matlab
AlgorithmFactory.refreshFromMetadata();
```

4. 冒烟测试验证：

```matlab
run_smoke_algorithm('MY-ALG', 'Problem', 'zdt1', 'PopulationSize', 20, 'Iterations', 5);
```

### 添加新评估器

继承 `Evaluator` 类，实现 `evaluate(x)` 方法：

```matlab
classdef MyEvaluator < Evaluator
    properties
        simulator
    end
    methods
        function obj = MyEvaluator(simulator)
            obj@Evaluator();
            obj.simulator = simulator;
        end

        function result = evaluate(obj, x)
            obj.simulator.setVariables(x);
            success = obj.simulator.run();
            if success
                objectives = obj.calculateObjectives();
                constraints = obj.calculateConstraints();
                result = obj.createSuccessResult(objectives, constraints);
            else
                result = obj.createErrorResult('Simulation failed');
            end
        end
    end
end
```

在 `evaluator_meta.json` 中注册即可被 GUI 自动发现。

### 从模板创建新项目

```matlab
% 复制模板
copyfile('example/_template', 'my_project', 'f');
cd('my_project');

% 编辑配置
edit('case_config.json');

% 运行
results = run_case('case_config.json');
```

---

## 常见问题排查

### 目标方向处理错误

症状：优化结果与预期相反。

原因：框架内部统一按最小化处理。`ExpressionEvaluator` 和领域专用评估器（如 `ADNProductionEvaluator`）会根据 `Objective.type` 自动处理方向转换。如果使用自定义评估器（`MyCaseEvaluator`），maximize 目标需要在 `evaluate()` 中手动取负。

```json
{
  "objectives": [
    {"name": "PROFIT", "type": "maximize"},
    {"name": "COST", "type": "minimize"}
  ]
}
```

### nodeMapping 配置错误

症状：`ConfigValidator` 报错 "检测到同时使用 nodeMapping 和 resultMapping"。

解决：统一使用 `nodeMapping` 格式，不要混用旧的 `resultMapping`：

```json
{
  "simulator": {
    "nodeMapping": {
      "variables": { "VAR": "\\Aspen\\Path" },
      "results": { "RES": "\\Aspen\\Path" }
    }
  }
}
```

### 表达式前缀错误

症状：`ConfigValidator` 报错 "检测到无效前缀"。

有效前缀只有四种：`x.`、`result.`、`param.`、`derived.`。`result.*` 引用必须在 `nodeMapping.results` 中有对应映射。

### Aspen COM 连接失败

症状：`actxserver('Apwn.Document')` 报错。

排查步骤：
1. 确认 Aspen Plus 已安装且许可证有效
2. 确认操作系统为 Windows
3. 在 MATLAB 中手动测试：`h = actxserver('Apwn.Document'); delete(h);`
4. 如果 RPC 错误频繁，增大 `retryDelay` 和 `maxRetries`

### 仿真超时

症状：优化过程中某些个体评估超时。

解决：增大 `evaluator.timeout` 和 `simulator.settings.timeout`。Aspen 仿真时间取决于模型复杂度，复杂模型可能需要 300-600 秒。

---

## 项目结构

```
MAPO/
+-- framework/
|   +-- algorithm/               -- 优化算法
|   |   +-- nsga2/              -- NSGA-II（多目标遗传算法）
|   |   +-- pso/                -- PSO（粒子群优化）
|   |   +-- ann_nsga2/          -- ANN-NSGA-II（代理辅助）
|   |   +-- AlgorithmBase.m     -- 算法抽象基类
|   |   +-- AlgorithmFactory.m  -- 算法工厂（元数据驱动）
|   |   +-- Individual.m        -- 个体类
|   |   +-- Population.m        -- 种群类
|   +-- problem/                 -- 问题定义
|   |   +-- evaluator/          -- 评估器
|   |   |   +-- ExpressionEvaluator.m    -- 表达式评估器（推荐）
|   |   |   +-- ADNProductionEvaluator.m -- ADN 专用
|   |   |   +-- ORCEvaluator.m           -- ORC 专用
|   |   |   +-- MyCaseEvaluator.m        -- 用户模板
|   |   +-- OptimizationProblem.m
|   |   +-- Variable.m / Objective.m / Constraint.m
|   +-- simulator/               -- 仿真器适配
|   |   +-- aspen/AspenPlusSimulator.m
|   |   +-- SimulatorConfig.m
|   +-- expression/              -- 表达式引擎
|   |   +-- ExpressionEngine.m   -- 词法分析 -> RPN -> 求值
|   |   +-- UnitRegistry.m      -- 物理单位系统
|   +-- core/                    -- 核心组件（Config, Logger, Parallel）
|   +-- module/                  -- 插件系统
|   +-- analysis/                -- 灵敏度分析
+-- gui/                         -- 图形用户界面
+-- example/
|   +-- _template/               -- 通用模板和冒烟测试
|   +-- ADN/                     -- ADN 生产优化示例
|   +-- R601/                    -- ORC 余热回收示例
|   +-- ASPL/                    -- 阿司匹林生产示例
+-- config/                      -- 全局配置样例
+-- docs/                        -- 文档
+-- quickstart.m                 -- 30 秒快速体验
+-- launchGUI.m                  -- GUI 启动入口
```

---

## 版本历史

### v2.1（当前版本）
- 新增图形用户界面（GUI），5 标签页设计
- 支持并行计算
- 新增灵敏度分析模块
- 新增 ANN-NSGA-II 代理辅助多目标算法
- GUI 算法/评估器列表改为 metadata 驱动
- 新增通用冒烟测试脚本
- 表达式验证功能集成到问题配置标签页

### v2.0
- 引入统一模板系统
- JSON 配置文件支持
- 模块化架构重构
- 多仿真器支持

### v1.0
- 初始版本
- NSGA-II 算法实现
- Aspen Plus 集成

---

## 许可证与联系方式

本项目采用 MIT 许可证。

项目维护者: 若羌 | Email: mapleccs@outlook.com

项目链接: [https://github.com/mapleccs/MAPO](https://github.com/mapleccs/MAPO)

---

**注意**: 使用本框架前，请确保您拥有合法的 Aspen Plus 和 MATLAB 许可证。


