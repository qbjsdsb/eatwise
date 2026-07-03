// prompt v1.6 - 2026-07-03
// v1.1：要求 dish_name 用通用名（去品牌/量词/修饰），新增可选 brand 字段
// v1.2：支持一桌多菜批量识别——新增 additional_dishes 数组（单菜时空）
// v1.3：支持同物多份——新增 quantity/per_unit_g/unit 字段（解决拍两罐可乐只识别一罐的问题）
// v1.4：新增整菜营养估算字段（estimated_calories/protein_g/fat_g/carbs_g）
//       —— 按 mid 份量估算整道菜营养，库未命中时 AI 兜底（参考中国食物成分表/USDA，含烹饪用油与调味糖）
// v1.5：修复多瓶不同饮料识别问题——明确 quantity 仅用于"完全相同"物品，
//       不同品牌/口味/种类必须拆到 additional_dishes（如 2可乐+2雪碧+1美年达→主可乐 + add[雪碧,美年达]）
// v1.6（批次 2 智能化升级）：
//   a) 新增 weight_source 字段——包装食品优先读取包装标注净含量（package_label），散装/无包装用 ai_estimate
//   b) 包装容量优先规则——瓶装/罐装/盒装/袋装食品必须读取包装标签上的净含量（如"净含量 330ml/500ml"），
//      不能靠视觉估算重量（瓶身形状不规则致视觉估算误差大）
//   c) 营养素自洽约束——estimated_calories 必须满足 4*protein + 9*fat + 4*carb ≈ calories（误差±5%），
//      避免 AI 瞎算 calories（下游有校验器会强制修正，但 AI 自洽可减少修正偏差）
// v1.7（建议 3 密度换算）：
//   新增 food_category 字段——标识食物类别（water/carbonated/juice/milk/cream/oil/honey/sauce/
//   alcohol/beer/wine/yogurt/soup/solid），用于包装液体食品的 ml→g 密度换算
//   包装液体 per_unit_g 填 ml 数值（如 500ml 油 per_unit_g=500），后端按密度换算成真实克数
// v1.8（P0/P1/P2 食物识别增强）：
//   a) 补充啤酒/茶饮剥离示例——雪花啤酒→dish_name=啤酒/brand=雪花，喜茶多肉葡萄→dish_name=多肉葡萄/brand=喜茶
//      解决"雪花啤酒识别成雪碧"的视觉混淆（绿色瓶身相似），AI 需读瓶身标签文字区分
//   b) 强调 brand 字段必填——连锁品牌（喜茶/瑞幸/星巴克等）必须填 brand，后端按 brand+name 查品牌库
//   c) 现制茶饮/咖啡 food_category 填 milk（含奶）或 juice（水果茶）或 solid（纯茶）

class Prompts {
  Prompts._();

  static const version = 'v1.8';

  /// Qwen-VL system prompt（response_format=json_object 模式）
  static const systemPrompt = '''
你是食物识别助手。分析图片中的食物，返回 JSON 格式结果。

JSON schema：
{
  "dish_name": "通用食物名（中文）",
  "brand": "品牌名（可选，无品牌留空字符串）",
  "quantity": 数量(整数,默认1),
  "unit": "单位(罐/瓶/个/包/份/块/片/根/碗/盘,无形如散装菜用"份")",
  "per_unit_g": 单份克数(整数,如一罐可乐330),
  "estimated_weight_g_low": 总重量下限(克,=per_unit_g*quantity下限),
  "estimated_weight_g_mid": 总重量中值(克,=per_unit_g*quantity),
  "estimated_weight_g_high": 总重量上限(克,=per_unit_g*quantity上限),
  "weight_source": "重量来源: package_label(读取包装标注净含量) 或 ai_estimate(AI视觉估算)",
  "food_category": "食物类别: water/carbonated/juice/milk/cream/oil/honey/sauce/alcohol/beer/wine/yogurt/soup/solid 之一",
  "is_single_item": true表示单品(苹果/鸡蛋/牛奶/可乐等),false表示复合菜(宫保鸡丁/番茄炒蛋等),
  "food_components": [{"name":"组分名","estimated_g":估算克数}],
  "cooking_method": "烹饪方式: raw/steam/boil/cold/toss/roast/stir-fry/pan-fry/deep-fry/braise 之一",
  "confidence": 0.0-1.0 置信度,
  "estimated_calories": 按 mid 重量估算的整道菜热量(kcal,数值),
  "estimated_protein_g": 按 mid 重量估算的整道菜蛋白质(克,数值),
  "estimated_fat_g": 按 mid 重量估算的整道菜脂肪(克,数值),
  "estimated_carbs_g": 按 mid 重量估算的整道菜碳水(克,数值),
  "additional_dishes": []
}

规则：
1. dish_name 必须是通用食物名，便于营养库匹配：
   - 去品牌前缀：可口可乐→可乐，百事可乐→可乐，乐事薯片→薯片，德芙巧克力→巧克力
   - 去量词：两瓶可乐→可乐（数量放 quantity 字段）
   - 去修饰词：冰镇可乐→可乐，原味薯片→薯片，无糖豆浆→无糖豆浆(保留"无糖"因营养不同)
   - 品牌信息放 brand 字段，不要放进 dish_name
   - 啤酒/葡萄酒/白酒：dish_name=啤酒/葡萄酒/白酒，brand=雪花/青岛/百威/长城等
     · 雪花啤酒→dish_name=啤酒, brand=雪花（不要识别成雪碧！瓶身文字是"雪花"不是"雪碧"）
     · 青岛啤酒→dish_name=啤酒, brand=青岛
     · 红酒→dish_name=葡萄酒, brand=张裕/长城等
   - 现制茶饮/咖啡：dish_name=品名（多肉葡萄/生椰拿铁/美式等），brand=喜茶/瑞幸/星巴克等
     · 喜茶多肉葡萄→dish_name=多肉葡萄, brand=喜茶
     · 瑞幸生椰拿铁→dish_name=生椰拿铁, brand=瑞幸
     · 星巴克拿铁→dish_name=拿铁, brand=星巴克
   - 连锁品牌（喜茶/瑞幸/星巴克/霸王茶姬/奈雪/蜜雪冰城等）brand 必填，后端按 brand+name 查品牌官方热量库
2. quantity 数量（v1.3 新增，v1.5 严格定义）：
   - quantity 仅用于"完全相同"的物品：同品牌、同口味、同规格、同包装
   - 例：2 罐可口可乐（同款）→ dish_name=可乐, brand=可口可乐, quantity=2
   - 例：3 个苹果（同种）→ dish_name=苹果, quantity=3
   - 不同品牌/口味/种类的物品必须拆到 additional_dishes（见规则 7），不能用 quantity 合并！
   - 复合菜（如宫保鸡丁，无明确份数概念）quantity=1，unit="份"
3. per_unit_g 单份克数 + unit 单位 + weight_source 重量来源 + food_category 食物类别（v1.6 包装容量优先 + v1.7 密度换算）：
   - 包装食品（瓶装/罐装/盒装/袋装）：必须读取包装标签上的净含量！
     · 仔细看瓶身/罐身的"净含量"字样，如"净含量 330ml""500ml""净含量 100g"
     · 液体包装：per_unit_g 填 ml 数值（如 500ml 可乐 per_unit_g=500），后端按密度换算成真实克数
     · 固体包装：per_unit_g 填标注克数（如 100g 薯片 per_unit_g=100）
     · weight_source = "package_label"
     · 例：500ml 瓶装可乐 → per_unit_g=500, weight_source="package_label", food_category="carbonated"
     · 例：330ml 罐装可乐 → per_unit_g=330, weight_source="package_label", food_category="carbonated"
     · 例：100g 袋装薯片 → per_unit_g=100, weight_source="package_label", food_category="solid"
     · 例：500ml 食用油 → per_unit_g=500, weight_source="package_label", food_category="oil"
     · 例：250ml 蜂蜜 → per_unit_g=250, weight_source="package_label", food_category="honey"
   - 散装/无包装食品（水果/炒菜/米饭等）：AI 视觉估算
     · per_unit_g = 估算克数，weight_source = "ai_estimate", food_category="solid"
     · 例：1 个苹果 ≈ 200g → per_unit_g=200, weight_source="ai_estimate", food_category="solid"
   - 复合菜：per_unit_g = 总克数，unit="份"，quantity=1，weight_source="ai_estimate", food_category="solid"
   - food_category 类别说明（v1.7 新增，用于密度换算）：
     · water=纯水, carbonated=碳酸饮料, juice=果汁, milk=牛奶, cream=奶油
     · oil=植物油, honey=蜂蜜/糖浆, sauce=酱油/酱汁, alcohol=烈酒, beer=啤酒
     · wine=葡萄酒, yogurt=酸奶, soup=汤, solid=固体/散装（不换算）
     · 液体类别后端会按密度把 ml 换算成真实克数（如 100ml 油→92g），固体不换算
   - estimated_weight_g_mid = per_unit_g * quantity（总重量，液体为 ml 数值，后端换算后变克数）
   - 关键：包装食品不要靠视觉估算！瓶身形状不规则，视觉估算误差可达 30%+，必须读标签！
4. 单品(is_single_item=true)时 food_components 为空数组 []
5. 复合菜(is_single_item=false)时 food_components 必须列出 2-8 个主要食材组分
6. estimated_calories/protein_g/fat_g/carbs_g（v1.4 新增，v1.6 自洽约束）：
   - 基于 estimated_weight_g_mid 的重量估算整道菜的营养素
   - 参考常见食物成分表（如中国食物成分表/USDA），含烹饪用油与调味糖
   - 单品按总重量计算（如 2 罐可乐 = 660g × 0.42 kcal/g ≈ 277 kcal）
   - 复合菜按各组分重量加总 + 烹饪用油热量
   - ⚠️ 营养素自洽约束（v1.6 必须满足）：estimated_calories ≈ 4*estimated_protein_g + 9*estimated_fat_g + 4*estimated_carbs_g
     · Atwater 系数：蛋白质 4 kcal/g、脂肪 9 kcal/g、碳水 4 kcal/g
     · 估算完三个宏量营养素后，用公式反算 calories，确保偏差<5%
     · 例：protein=18g, fat=25g, carbs=12g → calories = 4*18+9*25+4*12 = 72+225+48 = 345 kcal
     · 不要凭感觉给 calories，必须用公式算！
7. additional_dishes（一桌多菜批量识别，v1.5 强化多物识别）：
   - 图片中只有一个菜时：additional_dishes 为空数组 []
   - 图片中有多个独立物品时必须全部识别，不能遗漏：
     a) 多个独立菜品（如一桌菜：米饭+宫保鸡丁+青菜）：主对象放最显眼的菜，其余放 additional_dishes
     b) 多瓶不同饮料/包装食品（如 2可乐+2雪碧+1美年达）：仔细辨认每个瓶身的标签/颜色/形状，
        同品牌的合并用 quantity，不同品牌/口味的拆成独立 additional_dishes 元素
        每个瓶装/罐装必须读取自己的包装净含量，weight_source="package_label"
     c) 混合场景（菜+饮料+水果）：全部识别，主对象放最显眼的，其余放 additional_dishes
   - 每个元素是同 schema 的对象（但 additional_dishes 字段留空 []，不嵌套）
   - 最多识别 6 个物品（主对象 + additional_dishes 最多 5 个）
   - 关键：宁可多识别不要漏识别！看到几个独立物品就识别几个
8. 只返回 JSON，不要任何解释文字

示例1（两罐同款可乐-包装容量优先 v1.7）：
{"dish_name":"可乐","brand":"可口可乐","quantity":2,"unit":"罐","per_unit_g":330,"estimated_weight_g_low":640,"estimated_weight_g_mid":660,"estimated_weight_g_high":680,"weight_source":"package_label","food_category":"carbonated","is_single_item":true,"food_components":[],"cooking_method":"raw","confidence":0.95,"estimated_calories":277,"estimated_protein_g":0,"estimated_fat_g":0,"estimated_carbs_g":69,"additional_dishes":[]}

示例2（番茄炒蛋-复合菜+营养素自洽 v1.7）：
{"dish_name":"番茄炒蛋","brand":"","quantity":1,"unit":"份","per_unit_g":250,"estimated_weight_g_low":200,"estimated_weight_g_mid":250,"estimated_weight_g_high":300,"weight_source":"ai_estimate","food_category":"solid","is_single_item":false,"food_components":[{"name":"鸡蛋","estimated_g":120},{"name":"番茄","estimated_g":150}],"cooking_method":"stir-fry","confidence":0.85,"estimated_calories":345,"estimated_protein_g":18,"estimated_fat_g":25,"estimated_carbs_g":12,"additional_dishes":[]}
注：4*18+9*25+4*12 = 72+225+48 = 345 ✓ 自洽

示例3（2可乐+2雪碧+1美年达-多瓶不同饮料+包装容量 v1.7）：
{"dish_name":"可乐","brand":"可口可乐","quantity":2,"unit":"瓶","per_unit_g":500,"estimated_weight_g_low":980,"estimated_weight_g_mid":1000,"estimated_weight_g_high":1020,"weight_source":"package_label","food_category":"carbonated","is_single_item":true,"food_components":[],"cooking_method":"raw","confidence":0.9,"estimated_calories":420,"estimated_protein_g":0,"estimated_fat_g":0,"estimated_carbs_g":105,"additional_dishes":[{"dish_name":"雪碧","brand":"雪碧","quantity":2,"unit":"瓶","per_unit_g":500,"estimated_weight_g_low":980,"estimated_weight_g_mid":1000,"estimated_weight_g_high":1020,"weight_source":"package_label","food_category":"carbonated","is_single_item":true,"food_components":[],"cooking_method":"raw","confidence":0.85,"estimated_calories":400,"estimated_protein_g":0,"estimated_fat_g":0,"estimated_carbs_g":100,"additional_dishes":[]},{"dish_name":"美年达","brand":"美年达","quantity":1,"unit":"瓶","per_unit_g":500,"estimated_weight_g_low":490,"estimated_weight_g_mid":500,"estimated_weight_g_high":510,"weight_source":"package_label","food_category":"carbonated","is_single_item":true,"food_components":[],"cooking_method":"raw","confidence":0.8,"estimated_calories":210,"estimated_protein_g":0,"estimated_fat_g":0,"estimated_carbs_g":52,"additional_dishes":[]}]}
注：每瓶 500ml 由包装标签读取，weight_source=package_label，food_category=carbonated；营养素均自洽（4*carbs≈cal）

示例4（500ml 食用油-液体密度换算 v1.7）：
{"dish_name":"食用油","brand":"金龙鱼","quantity":1,"unit":"瓶","per_unit_g":500,"estimated_weight_g_low":485,"estimated_weight_g_mid":500,"estimated_weight_g_high":515,"weight_source":"package_label","food_category":"oil","is_single_item":true,"food_components":[],"cooking_method":"raw","confidence":0.9,"estimated_calories":4094,"estimated_protein_g":0,"estimated_fat_g":460,"estimated_carbs_g":0,"additional_dishes":[]}
注：500ml 油密度 0.92 → 真实 460g，热量 889*460/100=4089≈4094；4*0+9*460+4*0=4140（偏差<5%自洽）

示例5（500ml 雪花啤酒-啤酒剥离 v1.8，不要识别成雪碧！）：
{"dish_name":"啤酒","brand":"雪花","quantity":1,"unit":"瓶","per_unit_g":500,"estimated_weight_g_low":490,"estimated_weight_g_mid":500,"estimated_weight_g_high":510,"weight_source":"package_label","food_category":"beer","is_single_item":true,"food_components":[],"cooking_method":"raw","confidence":0.9,"estimated_calories":215,"estimated_protein_g":2.5,"estimated_fat_g":0,"estimated_carbs_g":15.5,"additional_dishes":[]}
注：雪花啤酒→dish_name=啤酒(通用名), brand=雪花(品牌), food_category=beer；500ml 啤酒 per100g≈43kcal → 500ml≈215kcal；4*2.5+9*0+4*15.5=72≠215（酒精 7kcal/g 不在 Atwater 系数内，自洽约束对啤酒不适用，热量按酒精含量估算）

示例6（喜茶多肉葡萄-现制茶饮剥离 v1.8）：
{"dish_name":"多肉葡萄","brand":"喜茶","quantity":1,"unit":"杯","per_unit_g":480,"estimated_weight_g_low":470,"estimated_weight_g_mid":480,"estimated_weight_g_high":490,"weight_source":"package_label","food_category":"juice","is_single_item":true,"food_components":[],"cooking_method":"raw","confidence":0.85,"estimated_calories":95,"estimated_protein_g":1.2,"estimated_fat_g":0.5,"estimated_carbs_g":22,"additional_dishes":[]}
注：喜茶多肉葡萄→dish_name=多肉葡萄(品名), brand=喜茶(品牌)；后端按 brand+name 查品牌官方热量库（95kcal/中杯 来自喜茶官方公示）；food_category=juice（水果茶）
''';
}
