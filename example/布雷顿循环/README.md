# 布雷顿循环多目标优化案例

## 📌 案例简介

本案例演示如何使用MAPO框架对布雷顿循环进行多目标优化，同时最大化热效率和净输出功率。

### 优化目标

1. **热效率** (thermal_efficiency) - 最大化
   - 定义：η = W_net / Q_in × 100%
   - 单位：%

2. **净输出功率** (net_power) - 最大化
   - 定义：W_net = W_turbine - W_compressor
   - 单位：kW

### 决策变量

| 变量 | 描述 | 范围 | 单位 |
|------|------|------|------|
| P_HP_in | 高压透平入口压力 | 17-35 | MPa |
| T_LP_in | 低压透平入口温度 | 500-600 | °C |
| split_ratio | 分流比 | 0.2-0.5 | - |
| P_LP_in | 低压透平入口压力 | 8-16 | MPa |
| P_inter | 中间压力 | 8-16 | MPa |
| T_comp_in | 压缩机入口温度 | 32-46 | °C |

### 约束条件

1. **最小热效率**: η ≥ 30%
2. **最小净功率**: W_net ≥ 1000 kW
3. **压力一致性**: P_HP_in ≥ P_LP_in
4. **中间压力范围**: P_LP_in ≤ P_inter ≤ P_HP_in

---

## 🚀 快速开始

### 方式一：使用简化模型（无需Aspen Plus）

```matlab
% 1. 进入案例目录
cd 'E:\Project\Chemical Design Competition\MAPO\example\布雷顿循环'

% 2. 添加框架路径
addpath(genpath('../../framework'))

% 3. 运行优化
run_brayton_optimization
```

**说明**：如果没有Aspen Plus模型文件，脚本会自动使用内置的简化模型进行优化。

### 方式二：使用Aspen Plus模型

```matlab
% 1. 准备Aspen Plus模型
%    - 将模型文件命名为: brayton_cycle.bkp
%    - 放置在当前目录: example/布雷顿循环/

% 2. 确保模型中的节点路径与配置一致
%    参考: brayton_config.json 中的 nodeMapping 部分

% 3. 运行优化
run_brayton_optimization
```

### 方式三：使用GUI

```matlab
% 1. 启动GUI
launchGUI()

% 2. 加载配置
%    点击"加载配置"，选择 brayton_config.json

% 3. 开始优化
%    点击"开始优化"按钮
```

---

## 📁 文件说明

```
布雷顿循环/
├── brayton_config.json              # 优化配置文件
├── run_brayton_optimization.m       # 运行脚本
├── README.md                        # 本文档
├── brayton_cycle.bkp               # Aspen Plus模型（可选）
├── results_nsga2/                  # 优化结果目录
│   ├── pareto_front.png            # Pareto前沿图
│   ├── pareto_solutions.csv        # Pareto最优解
│   └── optimization_results.mat    # MATLAB数据文件
└── logs/                           # 日志目录
    └── optimization_*.txt          # 优化日志
```

---

## 🔧 配置说明

### 算法参数

在 `brayton_config.json` 或 `run_brayton_optimization.m` 中可以调整：

```json
{
  "algorithm": {
    "type": "NSGA-II",
    "parameters": {
      "populationSize": 50,      // 种群大小
      "maxGenerations": 30,      // 最大迭代代数
      "crossoverRate": 0.9,      // 交叉概率
      "mutationRate": 1.0        // 变异率
    }
  }
}
```

**建议**：
- 快速测试：populationSize=20, maxGenerations=10
- 标准运行：populationSize=50, maxGenerations=30
- 精细优化：populationSize=100, maxGenerations=50

### 经济参数（可选）

```matlab
evaluator.interestRate = 0.12;        % 年利率
evaluator.systemLifetime = 20;        % 系统寿命(年)
evaluator.maintenanceFactor = 0.06;   % 维护因子
evaluator.operatingHours = 7200;      % 年运行小时数
evaluator.electricityPrice = 0.1;     % 电价($/kWh)
```

---

## 📊 结果分析

### Pareto前沿解释

优化完成后，会得到一组Pareto最优解，每个解代表热效率和净功率之间的一个权衡点：

- **左侧解**：高热效率，但净功率较低
- **右侧解**：高净功率，但热效率较低
- **中间解**：热效率和净功率的平衡

### 结果文件

1. **pareto_front.png** - Pareto前沿可视化
   - 横轴：热效率 (%)
   - 纵轴：净输出功率 (kW)

2. **pareto_solutions.csv** - Pareto最优解数据
   - 包含所有决策变量和目标值
   - 可用Excel打开进行进一步分析

3. **optimization_results.mat** - 完整优化数据
   - 包含所有评估历史
   - 可用于后处理和可视化

### 示例结果

```
序号 | P_HP_in | T_LP_in | split_ratio | P_LP_in | P_inter | T_comp_in | 热效率(%) | 净功率(kW)
-----|---------|---------|-------------|---------|---------|-----------|-----------|------------
1    | 28.50   | 580.00  | 0.35        | 12.00   | 14.00   | 38.00     | 42.50     | 5200.00
2    | 30.00   | 590.00  | 0.30        | 13.00   | 15.00   | 36.00     | 41.80     | 5500.00
3    | 32.00   | 595.00  | 0.28        | 14.00   | 16.00   | 35.00     | 40.50     | 5800.00
...
```

---

## 🎯 使用技巧

### 1. 调整变量范围

如果优化结果集中在边界，可以扩大变量范围：

```json
{
  "name": "P_HP_in",
  "lowerBound": 15,  // 从17改为15
  "upperBound": 40   // 从35改为40
}
```

### 2. 添加新约束

在 `BraytonCycleEvaluator.m` 的 `calculateConstraints` 方法中添加：

```matlab
% 约束6: 最大温度限制
constraints(end+1) = T_HP_out - 800;  % T_HP_out <= 800°C
```

### 3. 修改目标函数

在 `brayton_config.json` 中修改表达式：

```json
{
  "name": "specific_power",
  "type": "maximize",
  "expression": "result.W_net / result.mass_flow",
  "unit": "kJ/kg"
}
```

### 4. 使用表达式评估器

如果不想编写自定义评估器，可以使用 `ExpressionEvaluator`：

```json
{
  "evaluator": {
    "type": "ExpressionEvaluator",
    "timeout": 300
  }
}
```

然后在配置中定义所有目标和约束的表达式。

---

## 🐛 常见问题

### Q1: 优化运行很慢怎么办？

**A**:
1. 减小种群大小和迭代代数
2. 使用简化模型而非Aspen Plus
3. 启用并行计算（如果有多核CPU）

### Q2: Aspen Plus连接失败？

**A**:
1. 检查模型文件路径是否正确
2. 确保Aspen Plus已安装且版本兼容
3. 检查节点路径是否与模型一致
4. 尝试手动打开模型文件验证

### Q3: 所有解都违反约束？

**A**:
1. 检查约束是否过于严格
2. 调整变量初始范围
3. 增加种群大小以提高搜索能力
4. 检查约束定义是否正确

### Q4: Pareto前沿解太少？

**A**:
1. 增加种群大小
2. 增加迭代代数
3. 调整交叉和变异参数
4. 检查目标函数是否冲突明显

---

## 📚 参考资料

### 相关文档

- [MAPO框架使用指南](../../docs/user_guide.md)
- [GUI使用指南](../../docs/GUI_使用指南.md)
- [表达式引擎指南](../../docs/ExpressionEngine_Guide.md)
- [自定义评估器开发](../../docs/custom_evaluator_guide.md)

### 相关论文

1. Deb, K., et al. (2002). "A fast and elitist multiobjective genetic algorithm: NSGA-II." IEEE Transactions on Evolutionary Computation.

2. Saravanamuttoo, H. I., et al. (2017). "Gas Turbine Theory." Pearson Education.

3. Bejan, A. (2016). "Advanced Engineering Thermodynamics." John Wiley & Sons.

---

## 🤝 贡献

如果你改进了本案例或发现了问题，欢迎：

1. 提交Issue: https://github.com/your-repo/MAPO/issues
2. 提交Pull Request
3. 分享你的优化结果

---

## 📝 更新日志

- **2026-01-13**: 初始版本
  - 创建布雷顿循环优化案例
  - 支持简化模型和Aspen Plus模型
  - 实现多目标优化（热效率+净功率）

---

**作者**: MAPO开发团队
**最后更新**: 2026-01-13
**版本**: 1.0
