export const REALMS = [
  {
    name: "The Enchanted Forest",
    short: "Hutan Terpesona",
    floor: "forest_floor",
    enemyNames: ["Slime Rune", "Pixie Racun"],
    enemyAnims: [["slime_move", "slime_attack"], ["pixie_move", "pixie_attack"]],
    boss: "Giant Treant",
    pattern: "treant",
    colors: ["#27f5c7", "#c445ff"],
  },
  {
    name: "Crystal Caverns",
    short: "Gua Kristal",
    floor: "crystal_floor",
    enemyNames: ["Living Stalactite", "Crystal Bat"],
    enemyAnims: [["stalactite_move", "stalactite_attack"], ["crystal_bat_move", "crystal_bat_attack"]],
    boss: "Crystal Golem",
    pattern: "golem",
    colors: ["#5de7ff", "#7167ff"],
  },
  {
    name: "Forsaken Graveyard",
    short: "Makam Terkutuk",
    floor: "graveyard_floor",
    enemyNames: ["Flying Skull", "Banshee"],
    enemyAnims: [["skull_move", "skull_attack"], ["banshee_move", "banshee_attack"]],
    boss: "Necromancer",
    pattern: "necro",
    colors: ["#7fffd4", "#a65cff"],
  },
  {
    name: "Clockwork Tower",
    short: "Menara Mekanik",
    floor: "clockwork_floor",
    enemyNames: ["Gear Bomb", "Brass Drone"],
    enemyAnims: [["gear_bomb_move", "gear_bomb_attack"], ["brass_drone_move", "brass_drone_attack"]],
    boss: "Grand Automaton",
    pattern: "automaton",
    colors: ["#ffc75c", "#39ddff"],
  },
  {
    name: "Sunken Ruins",
    short: "Kuil Tenggelam",
    floor: "sunken_floor",
    enemyNames: ["Magic Jellyfish", "Ghost Manta"],
    enemyAnims: [["jellyfish_move", "jellyfish_attack"], ["manta_move", "manta_attack"]],
    boss: "Kraken Spirit",
    pattern: "kraken",
    colors: ["#31e8e8", "#ff5dde"],
  },
  {
    name: "Sky Islands",
    short: "Pulau Langit",
    floor: "sky_floor",
    enemyNames: ["Falling Ruin", "Harpy"],
    enemyAnims: [["ruin_move", "ruin_attack"], ["harpy_move", "harpy_attack"]],
    boss: "Zephyr Griffin",
    pattern: "griffin",
    colors: ["#c8f5ff", "#ffd15c"],
  },
  {
    name: "Volcanic Crags",
    short: "Tebing Vulkanik",
    floor: "volcanic_floor",
    enemyNames: ["Magma Meteor", "Young Drake"],
    enemyAnims: [["meteor_move", "meteor_attack"], ["drake_move", "drake_attack"]],
    boss: "Inferno Phoenix",
    pattern: "phoenix",
    colors: ["#ff713d", "#ff3f81"],
  },
  {
    name: "Frozen Citadel",
    short: "Benteng Es",
    floor: "frozen_floor",
    enemyNames: ["Ice Block", "Ice Gargoyle"],
    enemyAnims: [["ice_block_move", "ice_block_attack"], ["gargoyle_move", "gargoyle_attack"]],
    boss: "Frost Lich",
    pattern: "lich",
    colors: ["#a9f2ff", "#8b76ff"],
  },
  {
    name: "The Void Rift",
    short: "Celah Dimensi",
    floor: "void_floor",
    enemyNames: ["Void Orb", "Beholder"],
    enemyAnims: [["void_orb_move", "void_orb_attack"], ["beholder_move", "beholder_attack"]],
    boss: "Void Worm",
    pattern: "worm",
    colors: ["#ce55ff", "#29e6ff"],
  },
  {
    name: "The Demon Lord's Throne",
    short: "Singgasana Iblis",
    floor: "throne_floor",
    enemyNames: ["Corrupt Slime", "Brass Executioner"],
    enemyAnims: [["corrupt_slime_move", "corrupt_slime_attack"], ["executioner_move", "executioner_attack"]],
    boss: "Demon Gunsmith",
    pattern: "gunsmith",
    colors: ["#ff405f", "#23e8ff"],
  },
];

export const SKINS = [
  ["Rune Cadet", "Arc Bolt Barrage", "Aegis Surge", "Astral Rail", "#58e9ff"],
  ["Ember Witch", "Flame Fan", "Phoenix Dash", "Solar Inferno", "#ff7447"],
  ["Frost Valkyrie", "Icicle Lances", "Frozen Time", "Absolute Zero", "#a9f2ff"],
  ["Storm Corsair", "Chain Volley", "Thunderstep", "Tempest Crown", "#b75cff"],
  ["Verdant Ranger", "Thorn Burst", "Vine Prison", "Worldroot Bloom", "#57f08b"],
  ["Crystal Sentinel", "Prism Shot", "Mirror Guard", "Diamond Cataclysm", "#70cfff"],
  ["Grave Oracle", "Soul Scythes", "Wraith Clone", "Eclipse Requiem", "#b77aff"],
  ["Clockwork Duchess", "Gear Mines", "Time Overdrive", "Chrono Arsenal", "#ffc45d"],
  ["Abyss Diver", "Bubble Torpedoes", "Tidal Vacuum", "Leviathan Wave", "#37e8d6"],
  ["Sky Lancer", "Wind Spears", "Falcon Dive", "Heaven Splitter", "#e3f8ff"],
  ["Magma Reaver", "Lava Mortar", "Eruption Step", "Caldera Judgment", "#ff552f"],
  ["Frostfire Twin", "Steam Blades", "Thermal Swap", "Paradox Nova", "#ff83cf"],
  ["Void Walker", "Rift Needles", "Blink Collapse", "Event Horizon", "#a83dff"],
  ["Star Priestess", "Comet Rain", "Zodiac Ward", "Celestial Choir", "#ffe67a"],
  ["Bloodmoon Hunter", "Crimson Ricochet", "Lunar Hunt", "Blood Moon Verdict", "#ff476d"],
  ["Dragon Empress", "Dragonfire Orbs", "Wingstorm", "Thousand Scale Ascension", "#ffb83d"],
  ["Seraph Gunner", "Holy Barrage", "Halo Recall", "Sevenfold Heaven", "#fff0a5"],
  ["Demonbreaker", "Hellchain Shot", "Abyss Counter", "Gate of Ruin", "#ff3858"],
  ["Astral Sovereign", "Galaxy Pulse", "Orbit Arsenal", "Constellation Cannon", "#7798ff"],
  ["Omega Arcanum", "Reality Shards", "Infinite Chamber", "Ten Realm Annihilation", "#ffffff"],
].map(([name, skillOne, skillTwo, ultimate, color], index) => ({
  id: index,
  key: `SKIN_${String(index + 1).padStart(2, "0")}_SHEET`,
  combatKey: `SKIN_${String(index + 1).padStart(2, "0")}_COMBAT`,
  finishKey: `SKIN_${String(index + 1).padStart(2, "0")}_FINISH`,
  name,
  skillOne,
  skillTwo,
  ultimate,
  color,
  price: index === 0 ? 0 : 150 + index * index * 55,
  power: 1 + index * 0.08,
}));

export const POWERUPS = [
  { id: "gatling", name: "Gatling Rune", icon: "gatling_rune", description: "Fire rate ekstrem · 10 dtk" },
  { id: "shield", name: "Aegis Shield", icon: "aegis_shield", description: "Menahan satu serangan" },
  { id: "nova", name: "Nova Bomb", icon: "nova_bomb", description: "Bersihkan musuh kecil" },
  { id: "boots", name: "Pegasus Boots", icon: "pegasus_boots", description: "Gerak & lompat meningkat · 10 dtk" },
];

export const BUFFS = [
  { id: "split", name: "Split Shot", icon: "split_shot", max: 2, description: ["Tembakan membelah menjadi 3", "Tembakan membelah menjadi 5"] },
  { id: "piercing", name: "Piercing Ammo", icon: "piercing_ammo", max: 3, description: ["Menembus +1 target", "Menembus +2 target", "Menembus +3 target"] },
  { id: "fire", name: "Fire Bullets", icon: "fire_bullets", max: 2, description: ["Membakar musuh", "Burn lebih kuat dan meledak"] },
  { id: "ice", name: "Ice Bullets", icon: "ice_bullets", max: 2, description: ["Memperlambat musuh", "Slow lebih kuat"] },
  { id: "lightning", name: "Lightning Bullets", icon: "lightning_bullets", max: 2, description: ["Menyambar 1 target", "Menyambar 2 target"] },
  { id: "vampiric", name: "Vampiric Chamber", icon: "vampiric_chamber", max: 1, description: ["50 kill memulihkan 1 HP"] },
  { id: "heavy", name: "Heavy Caliber", icon: "heavy_caliber", max: 2, description: ["+50% damage, fire rate turun", "+100% damage, peluru lebih besar"] },
];

export function makeBuffState() {
  return Object.fromEntries(BUFFS.map((buff) => [buff.id, 0]));
}

export function pickBuffChoices(levels, count = 3) {
  const available = BUFFS.filter((buff) => (levels[buff.id] || 0) < buff.max);
  // Never offer a maxed rune (picking it would waste the camp); fewer than
  // `count` cards is fine. Only when everything is maxed fall back to all.
  const pool = available.length ? available : BUFFS;
  return [...pool].sort(() => Math.random() - 0.5).slice(0, count);
}
