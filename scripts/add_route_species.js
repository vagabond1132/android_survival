// Add associated_species to 30 northern routes
const fs = require('fs');
const path = 'assets/data/routes.json';
const d = JSON.parse(fs.readFileSync(path, 'utf-8'));

// 北方 30 条路线 + 关联动植物 (鲁晋冀豫)
const routeSpeciesMap = {
  'laoshan_5t4p': { province: '山东', plants: ['plant_shepherd_purse','plant_dandelion','plant_chinese_toon','plant_chenopodium'], animals: ['animal_gloydius_brevicaudus','animal_zaocys'] },
  'taishan_xx': { province: '山东', plants: ['plant_shepherd_purse','plant_dandelion','plant_chenopodium','plant_armeniaca'], animals: ['animal_gloydius_brevicaudus','animal_zaocys','animal_vulpes'] },
  'taishan_dong': { province: '山东', plants: ['plant_dandelion','plant_chenopodium','plant_hippophae'], animals: ['animal_gloydius_brevicaudus','animal_sus_scrofa'] },
  'laoshan_jufeng': { province: '山东', plants: ['plant_chenopodium','plant_hippophae','plant_lonicera'], animals: ['animal_zaocys','animal_gloydius_brevicaudus'] },
  'kunyu_shan': { province: '山东', plants: ['plant_chenopodium','plant_shepherd_purse','plant_armeniaca'], animals: ['animal_gloydius_ussuriensis','animal_zaocys'] },
  'yi_meng_shan': { province: '山东', plants: ['plant_shepherd_purse','plant_chenopodium','plant_chinese_toon','plant_armeniaca'], animals: ['animal_sus_scrofa','animal_zaocys'] },
  'hengshan_xx': { province: '山西', plants: ['plant_hippophae','plant_dandelion','plant_shepherd_purse','plant_glehnia'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes','animal_ursus_thibetanus'] },
  'wutaishan': { province: '山西', plants: ['plant_dandelion','plant_hippophae','plant_shepherd_purse','plant_saposhnikovia'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes','animal_sus_scrofa'] },
  'lu_liang_shan': { province: '山西', plants: ['plant_hippophae','plant_dandelion','plant_chenopodium','plant_polygala'], animals: ['animal_marmota','animal_vulpes','animal_sus_scrofa'] },
  'taihang_south': { province: '山西/河南', plants: ['plant_shepherd_purse','plant_dandelion','plant_chenopodium','plant_armeniaca','plant_oenanthe','plant_cicuta'], animals: ['animal_gloydius_brevicaudus_sin','animal_zaocys','animal_vulpes','animal_chiroptera'] },
  'taihang_north': { province: '河北/山西', plants: ['plant_shepherd_purse','plant_dandelion','plant_chenopodium','plant_saposhnikovia'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes','animal_meles'] },
  'hengshan_xx_hb': { province: '河北', plants: ['plant_chenopodium','plant_shepherd_purse','plant_dandelion','plant_armeniaca'], animals: ['animal_gloydius_brevicaudus_sin','animal_zaocys','animal_meles'] },
  'xiaowutaishan': { province: '河北', plants: ['plant_chenopodium','plant_dandelion','plant_saposhnikovia','plant_glehnia'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes'] },
  'bashang_grassland': { province: '河北', plants: ['plant_chenopodium','plant_hippophae','plant_saposhnikovia'], animals: ['animal_marmota','animal_vulpes','animal_vulpes'] },
  'yanshan_xx': { province: '河北', plants: ['plant_shepherd_purse','plant_dandelion','plant_armeniaca','plant_hippophae'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes','animal_meles'] },
  'songshan_xx': { province: '河南', plants: ['plant_lonicera','plant_forsythia','plant_adenophora','plant_pueraria_lobata','plant_gelsemium'], animals: ['animal_agkistrodon','animal_protobothrops','animal_trimeresurus','animal_naja','animal_bungarus','animal_sus_scrofa','animal_ursus_thibetanus','animal_hirudo'] },
  'songshan_shaolin': { province: '河南', plants: ['plant_lonicera','plant_pueraria_lobata','plant_gelsemium'], animals: ['animal_agkistrodon','animal_sus_scrofa'] },
  'funiu_shan': { province: '河南', plants: ['plant_pueraria_lobata','plant_gelsemium','plant_forsythia','plant_ligusticum'], animals: ['animal_protobothrops','animal_trimeresurus','animal_sus_scrofa','animal_ursus_thibetanus'] },
  'baotianman': { province: '河南', plants: ['plant_pueraria_lobata','plant_dioscorea_opposita','plant_adenophora'], animals: ['animal_protobothrops','animal_sus_scrofa','animal_chiroptera'] },
  'jigong_shan': { province: '河南', plants: ['plant_lonicera','plant_chinese_toon','plant_shepherd_purse'], animals: ['animal_gloydius_brevicaudus','animal_zaocys'] },
  'huangshian': { province: '河南', plants: ['plant_pueraria_lobata','plant_lonicera','plant_adenophora'], animals: ['animal_sus_scrofa','animal_chiroptera'] },
  'yunyang_xx': { province: '河南', plants: ['plant_shepherd_purse','plant_dandelion','plant_pueraria_lobata'], animals: ['animal_gloydius_brevicaudus','animal_sus_scrofa'] },
  'tongbai_shan': { province: '河南', plants: ['plant_pueraria_lobata','plant_adenophora','plant_ligusticum'], animals: ['animal_protobothrops','animal_sus_scrofa'] },
  'taishan_south': { province: '山东', plants: ['plant_shepherd_purse','plant_dandelion','plant_chinese_toon'], animals: ['animal_gloydius_brevicaudus','animal_zaocys'] },
  'penglai': { province: '山东', plants: ['plant_shepherd_purse','plant_chinese_toon','plant_armeniaca'], animals: ['animal_gloydius_ussuriensis','animal_zaocys'] },
  'weihai_xx': { province: '山东', plants: ['plant_shepherd_purse','plant_chinese_toon','plant_hippophae'], animals: ['animal_gloydius_ussuriensis'] },
  'wudang_xx': { province: '湖北(不属北方,但经典)', plants: ['plant_dioscorea_opposita','plant_adenophora','plant_ligusticum'], animals: ['animal_protobothrops','animal_sus_scrofa'] },
  'emeishan': { province: '四川(不属北方)', plants: [], animals: [] },
  'qinling': { province: '陕西/河南', plants: ['plant_pueraria_lobata','plant_gelsemium','plant_dioscorea_opposita','plant_ligusticum'], animals: ['animal_agkistrodon','animal_gloydius_brevicaudus','animal_sus_scrofa','animal_ursus_thibetanus'] }
};

let updated = 0;
d.routes.forEach(r => {
  if (routeSpeciesMap[r.id]) {
    const map = routeSpeciesMap[r.id];
    r.associated_species = {
      province: map.province,
      plants: map.plants,
      animals: map.animals,
      insects: [],
      mushrooms: []
    };
    updated++;
  }
});

fs.writeFileSync(path, JSON.stringify(d, null, 2));
console.log('更新路线:', updated, '总计:', d.routes.length);
