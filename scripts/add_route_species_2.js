// Real route ids (from routes.json inspection)
const fs = require('fs');
const path = 'assets/data/routes.json';
const d = JSON.parse(fs.readFileSync(path, 'utf-8'));

// Use actual IDs
const routeSpeciesMap = {
  'route_lao_mountain': { province: '河南', plants: ['plant_lonicera','plant_pueraria_lobata','plant_gelsemium','plant_adenophora'], animals: ['animal_agkistrodon','animal_protobothrops','animal_sus_scrofa'] },
  'route_tai_mountain': { province: '山东', plants: ['plant_shepherd_purse','plant_dandelion','plant_chinese_toon','plant_chenopodium'], animals: ['animal_gloydius_brevicaudus','animal_zaocys'] },
  'route_taishan_dong': { province: '河北', plants: ['plant_shepherd_purse','plant_dandelion','plant_chenopodium','plant_saposhnikovia'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes'] },
  'route_wutaishan': { province: '山西', plants: ['plant_dandelion','plant_hippophae','plant_shepherd_purse','plant_saposhnikovia'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes'] },
  'route_hengshan_north': { province: '山西', plants: ['plant_hippophae','plant_shepherd_purse','plant_saposhnikovia'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes'] },
  'route_bashang_grassland': { province: '河北', plants: ['plant_chenopodium','plant_hippophae','plant_saposhnikovia'], animals: ['animal_marmota','animal_vulpes'] },
  'route_songshan': { province: '河南', plants: ['plant_lonicera','plant_forsythia','plant_adenophora','plant_pueraria_lobata','plant_gelsemium'], animals: ['animal_agkistrodon','animal_protobothrops','animal_sus_scrofa'] },
  'route_laiyang_tashan': { province: '山东', plants: ['plant_chenopodium','plant_hippophae','plant_armeniaca'], animals: ['animal_gloydius_brevicaudus','animal_zaocys'] },
  'route_kongshan': { province: '山东', plants: ['plant_chenopodium','plant_shepherd_purse','plant_hippophae','plant_lonicera'], animals: ['animal_gloydius_brevicaudus','animal_zaocys'] },
  'route_mengshan': { province: '山东', plants: ['plant_chenopodium','plant_shepherd_purse','plant_armeniaca'], animals: ['animal_gloydius_brevicaudus','animal_zaocys','animal_sus_scrofa'] },
  'route_baishishan': { province: '河北', plants: ['plant_chenopodium','plant_hippophae','plant_armeniaca'], animals: ['animal_gloydius_brevicaudus_sin','animal_meles'] },
  'route_yuntaishan': { province: '河南', plants: ['plant_pueraria_lobata','plant_lonicera','plant_adenophora'], animals: ['animal_agkistrodon','animal_sus_scrofa'] },
  'route_baodu_zhai': { province: '河北', plants: ['plant_chenopodium','plant_saposhnikovia'], animals: ['animal_vulpes'] },
  'route_jiyu_bay': { province: '河南', plants: ['plant_lonicera','plant_chinese_toon','plant_shepherd_purse'], animals: ['animal_gloydius_brevicaudus'] },
  'route_wutaishan_bodhisattva': { province: '山西', plants: ['plant_dandelion','plant_hippophae','plant_saposhnikovia'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes','animal_sus_scrofa'] },
  'route_lvliangshans': { province: '山西', plants: ['plant_hippophae','plant_saposhnikovia','plant_polygala'], animals: ['animal_marmota','animal_vulpes'] },
  'route_taishan_baisong': { province: '山东', plants: ['plant_shepherd_purse','plant_dandelion','plant_chinese_toon'], animals: ['animal_gloydius_brevicaudus','animal_zaocys'] },
  'route_wutaishan_nantai': { province: '山西', plants: ['plant_dandelion','plant_hippophae','plant_saposhnikovia'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes'] },
  'route_baixiang': { province: '河南', plants: ['plant_pueraria_lobata','plant_lonicera','plant_adenophora'], animals: ['animal_protobothrops','animal_sus_scrofa'] },
  'route_xinglong_mt': { province: '河北', plants: ['plant_chenopodium','plant_shepherd_purse','plant_hippophae'], animals: ['animal_gloydius_brevicaudus_sin','animal_vulpes'] },
  'route_lushan_shandong': { province: '山东', plants: ['plant_shepherd_purse','plant_chenopodium','plant_armeniaca'], animals: ['animal_zaocys'] },
  'route_lao_mt_qing': { province: '山东', plants: ['plant_chenopodium','plant_shepherd_purse','plant_armeniaca'], animals: ['animal_gloydius_brevicaudus','animal_zaocys'] },
  'route_laojunshan': { province: '河南', plants: ['plant_lonicera','plant_pueraria_lobata','plant_gelsemium'], animals: ['animal_protobothrops','animal_sus_scrofa'] },
  'route_funiushan': { province: '河南', plants: ['plant_pueraria_lobata','plant_gelsemium','plant_forsythia','plant_ligusticum'], animals: ['animal_protobothrops','animal_sus_scrofa','animal_ursus_thibetanus'] },
  'route_wu_mt_xi': { province: '河北', plants: ['plant_dandelion','plant_chenopodium','plant_saposhnikovia'], animals: ['animal_vulpes'] },
  'route_feng_mt_zh': { province: '河南', plants: ['plant_pueraria_lobata','plant_lonicera'], animals: ['animal_agkistrodon','animal_sus_scrofa'] },
  'route_yan_mt': { province: '山西', plants: ['plant_saposhnikovia','plant_polygala'], animals: ['animal_meles','animal_vulpes'] },
  'route_pingyao': { province: '山西', plants: ['plant_chenopodium','plant_shepherd_purse'], animals: [] },
  'route_mt_yi': { province: '山东', plants: ['plant_chenopodium','plant_shepherd_purse','plant_armeniaca'], animals: ['animal_gloydius_brevicaudus'] },
  'route_yantai_mt': { province: '山东', plants: ['plant_chenopodium','plant_hippophae'], animals: ['animal_gloydius_ussuriensis'] },
  'route_lu_mt_lc': { province: '河北', plants: ['plant_chenopodium','plant_saposhnikovia'], animals: ['animal_vulpes'] },
  'route_qingdao_lao_jin': { province: '山东', plants: ['plant_chenopodium','plant_shepherd_purse','plant_hippophae','plant_lonicera'], animals: ['animal_gloydius_brevicaudus','animal_zaocys'] },
  'route_mengshan_dong': { province: '山东', plants: ['plant_chenopodium','plant_shepherd_purse','plant_armeniaca'], animals: ['animal_zaocys'] },
  'route_songshanjp': { province: '河南', plants: ['plant_lonicera','plant_forsythia','plant_pueraria_lobata','plant_gelsemium'], animals: ['animal_agkistrodon','animal_protobothrops','animal_sus_scrofa'] },
  'route_penglai_bz': { province: '山东', plants: ['plant_shepherd_purse','plant_chinese_toon','plant_armeniaca'], animals: ['animal_zaocys'] },
  'route_changshou_shan': { province: '河北', plants: ['plant_chenopodium','plant_hippophae','plant_armeniaca'], animals: ['animal_vulpes'] },
  'route_yingxian': { province: '山西', plants: ['plant_saposhnikovia','plant_polygala'], animals: ['animal_meles'] },
  'route_zhongtiao_mt': { province: '山西', plants: ['plant_hippophae','plant_saposhnikovia'], animals: ['animal_gloydius_brevicaudus_sin'] },
  'route_lvliang_bw': { province: '山西', plants: ['plant_hippophae','plant_saposhnikovia','plant_polygala'], animals: ['animal_marmota','animal_vulpes','animal_sus_scrofa'] },
  'route_yuntaishan_jin': { province: '河南', plants: ['plant_pueraria_lobata','plant_lonicera','plant_adenophora'], animals: ['animal_agkistrodon','animal_sus_scrofa'] }
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
console.log('更新路线:', updated, '/ 总计:', d.routes.length);
