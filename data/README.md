# 数值配置

`balance.json` 为唯一可信源，启动时由 `scripts/game_data.gd` 加载并校验。

## 文件

- `balance.json` – 汇总，包含 `weapons` / `passives` / `enemies` / `spawn`
- `weapons.json` / `passives.json` / `enemies.json` / `spawn.json` – 拆分副本，便于编辑

编辑后只需改 `balance.json`（或同步拆分文件），游戏与测试会自动校验。

## weapons

```json
{
  "dagger": {
	"name": "飞刀",
	"color": {"r":0.65,"g":0.9,"b":1.0},
	"desc": "自动射向最近的敌人，可穿透",
	"levels": [
	  {"count":1,"dmg":12.0,"cd":0.85,"pierce":1}
	]
  }
}
```

- `color` 支持 `{"r":…,"g":…,"b":…,"a":1}`、hex 字符串 `"#AABBCC"` 或数组
- `dagger` 需 `count/dmg/cd/pierce`，`orbit` 需 `orbs/dmg/radius/rot`，`lightning` 需 `cd/strikes/dmg/aoe`，`aura` 需 `radius/dps`
- `levels` 长度即最大等级，缺失字段会在启动校验中报错

## passives

```json
{
  "damage": {"name":"力量祝福","desc":"所有伤害 +15%","max":5,"color":{"r":1.0,"g":0.45,"b":0.4}}
}
```

`max` 为可叠加次数。

## enemies

```json
{
  "slime": {"hp":18.0,"spd":72.0,"dmg":8.0,"r":13.0,"xp":1,"color":{"r":0.4,"g":0.85,"b":0.45}}
}
```

`r` 为碰撞半径，`xp` 为掉落经验。

## spawn

```json
{
  "arena":2600.0,
  "goal_time":300.0,
  "max_enemies":170,
  "spawn_radius":820.0,
  "spawn_interval":{"base":1.8,"per_second":0.006,"min":0.45,"max":1.8},
  "batch":{"base":1,"per_45sec":1},
  "elite_interval":40.0,
  "boss_times":[150.0,250.0],
  "kind_thresholds":[
	{"elapsed_lt":25.0,"weights":{"slime":1.0}}
  ],
  "enemy_scaling":{"hp_per_sec":0.011,"speed_per_sec":0.0005,"speed_max":1.2,"speed_rand_min":0.92,"speed_rand_max":1.08,"dmg_per_sec":0.0022}
}
```

- `spawn_interval` 计算 `clampf(base - elapsed*per_second, min, max)`
- `batch = base + int(elapsed/45)`
- `kind_thresholds` 按 `elapsed` 从小到大匹配首个 `elapsed_lt`，按 `weights` 概率抽取

## 校验

`GameData.ensure_loaded()` 在 `game.gd:_ready` 调用，输出：

- `get_errors()` – 缺失/类型错误，阻断性（会回退默认值）
- `get_warnings()` – 可恢复

新增武器/被动只需在 `balance.json` 加 ID 与 `levels`，`game.gd:_roll_cards` 与 `player.gd` 会自动识别，无需改核心流程。

## 工具

```bash
make test   # 会触发校验，错误以 [GameData] 打印
```
