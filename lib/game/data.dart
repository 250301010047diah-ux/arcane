import 'dart:math';
import 'dart:ui';

Color hex(String value) {
  final v = value.replaceFirst('#', '');
  return Color(int.parse(v.length == 6 ? 'FF$v' : v, radix: 16));
}

String pad2(int value) => value.toString().padLeft(2, '0');

class Realm {
  final String name, short, floor, boss, pattern;
  final List<String> enemyNames;
  final List<List<String>> enemyAnims;
  final List<Color> colors;
  const Realm(this.name, this.short, this.floor, this.enemyNames, this.enemyAnims, this.boss, this.pattern, this.colors);
}

final List<Realm> realms = [
  Realm('The Enchanted Forest', 'Hutan Terpesona', 'forest_floor', ['Slime Rune', 'Pixie Racun'],
      [['slime_move', 'slime_attack'], ['pixie_move', 'pixie_attack']], 'Giant Treant', 'treant', [hex('#27f5c7'), hex('#c445ff')]),
  Realm('Crystal Caverns', 'Gua Kristal', 'crystal_floor', ['Living Stalactite', 'Crystal Bat'],
      [['stalactite_move', 'stalactite_attack'], ['crystal_bat_move', 'crystal_bat_attack']], 'Crystal Golem', 'golem', [hex('#5de7ff'), hex('#7167ff')]),
  Realm('Forsaken Graveyard', 'Makam Terkutuk', 'graveyard_floor', ['Flying Skull', 'Banshee'],
      [['skull_move', 'skull_attack'], ['banshee_move', 'banshee_attack']], 'Necromancer', 'necro', [hex('#7fffd4'), hex('#a65cff')]),
  Realm('Clockwork Tower', 'Menara Mekanik', 'clockwork_floor', ['Gear Bomb', 'Brass Drone'],
      [['gear_bomb_move', 'gear_bomb_attack'], ['brass_drone_move', 'brass_drone_attack']], 'Grand Automaton', 'automaton', [hex('#ffc75c'), hex('#39ddff')]),
  Realm('Sunken Ruins', 'Kuil Tenggelam', 'sunken_floor', ['Magic Jellyfish', 'Ghost Manta'],
      [['jellyfish_move', 'jellyfish_attack'], ['manta_move', 'manta_attack']], 'Kraken Spirit', 'kraken', [hex('#31e8e8'), hex('#ff5dde')]),
  Realm('Sky Islands', 'Pulau Langit', 'sky_floor', ['Falling Ruin', 'Harpy'],
      [['ruin_move', 'ruin_attack'], ['harpy_move', 'harpy_attack']], 'Zephyr Griffin', 'griffin', [hex('#c8f5ff'), hex('#ffd15c')]),
  Realm('Volcanic Crags', 'Tebing Vulkanik', 'volcanic_floor', ['Magma Meteor', 'Young Drake'],
      [['meteor_move', 'meteor_attack'], ['drake_move', 'drake_attack']], 'Inferno Phoenix', 'phoenix', [hex('#ff713d'), hex('#ff3f81')]),
  Realm('Frozen Citadel', 'Benteng Es', 'frozen_floor', ['Ice Block', 'Ice Gargoyle'],
      [['ice_block_move', 'ice_block_attack'], ['gargoyle_move', 'gargoyle_attack']], 'Frost Lich', 'lich', [hex('#a9f2ff'), hex('#8b76ff')]),
  Realm('The Void Rift', 'Celah Dimensi', 'void_floor', ['Void Orb', 'Beholder'],
      [['void_orb_move', 'void_orb_attack'], ['beholder_move', 'beholder_attack']], 'Void Worm', 'worm', [hex('#ce55ff'), hex('#29e6ff')]),
  Realm("The Demon Lord's Throne", 'Singgasana Iblis', 'throne_floor', ['Corrupt Slime', 'Brass Executioner'],
      [['corrupt_slime_move', 'corrupt_slime_attack'], ['executioner_move', 'executioner_attack']], 'Demon Gunsmith', 'gunsmith', [hex('#ff405f'), hex('#23e8ff')]),
];

class Skin {
  final int id;
  final String name, skillOne, skillTwo, ultimate;
  final Color color;
  final int price;
  final double power;
  Skin(this.id, this.name, this.skillOne, this.skillTwo, this.ultimate, this.color)
      : price = id == 0 ? 0 : 150 + id * id * 55,
        power = 1 + id * 0.08;
  String get key => 'SKIN_${pad2(id + 1)}_SHEET';
  String get combatKey => 'SKIN_${pad2(id + 1)}_COMBAT';
  String get finishKey => 'SKIN_${pad2(id + 1)}_FINISH';
}

final List<Skin> skins = () {
  const raw = [
    ['Rune Cadet', 'Arc Bolt Barrage', 'Aegis Surge', 'Astral Rail', '#58e9ff'],
    ['Ember Witch', 'Flame Fan', 'Phoenix Dash', 'Solar Inferno', '#ff7447'],
    ['Frost Valkyrie', 'Icicle Lances', 'Frozen Time', 'Absolute Zero', '#a9f2ff'],
    ['Storm Corsair', 'Chain Volley', 'Thunderstep', 'Tempest Crown', '#b75cff'],
    ['Verdant Ranger', 'Thorn Burst', 'Vine Prison', 'Worldroot Bloom', '#57f08b'],
    ['Crystal Sentinel', 'Prism Shot', 'Mirror Guard', 'Diamond Cataclysm', '#70cfff'],
    ['Grave Oracle', 'Soul Scythes', 'Wraith Clone', 'Eclipse Requiem', '#b77aff'],
    ['Clockwork Duchess', 'Gear Mines', 'Time Overdrive', 'Chrono Arsenal', '#ffc45d'],
    ['Abyss Diver', 'Bubble Torpedoes', 'Tidal Vacuum', 'Leviathan Wave', '#37e8d6'],
    ['Sky Lancer', 'Wind Spears', 'Falcon Dive', 'Heaven Splitter', '#e3f8ff'],
    ['Magma Reaver', 'Lava Mortar', 'Eruption Step', 'Caldera Judgment', '#ff552f'],
    ['Frostfire Twin', 'Steam Blades', 'Thermal Swap', 'Paradox Nova', '#ff83cf'],
    ['Void Walker', 'Rift Needles', 'Blink Collapse', 'Event Horizon', '#a83dff'],
    ['Star Priestess', 'Comet Rain', 'Zodiac Ward', 'Celestial Choir', '#ffe67a'],
    ['Bloodmoon Hunter', 'Crimson Ricochet', 'Lunar Hunt', 'Blood Moon Verdict', '#ff476d'],
    ['Dragon Empress', 'Dragonfire Orbs', 'Wingstorm', 'Thousand Scale Ascension', '#ffb83d'],
    ['Seraph Gunner', 'Holy Barrage', 'Halo Recall', 'Sevenfold Heaven', '#fff0a5'],
    ['Demonbreaker', 'Hellchain Shot', 'Abyss Counter', 'Gate of Ruin', '#ff3858'],
    ['Astral Sovereign', 'Galaxy Pulse', 'Orbit Arsenal', 'Constellation Cannon', '#7798ff'],
    ['Omega Arcanum', 'Reality Shards', 'Infinite Chamber', 'Ten Realm Annihilation', '#ffffff'],
  ];
  return [for (var i = 0; i < raw.length; i++) Skin(i, raw[i][0], raw[i][1], raw[i][2], raw[i][3], hex(raw[i][4]))];
}();

class PowerUp {
  final String id, name, icon, description;
  const PowerUp(this.id, this.name, this.icon, this.description);
}

const powerups = [
  PowerUp('gatling', 'Gatling Rune', 'gatling_rune', 'Fire rate ekstrem · 10 dtk'),
  PowerUp('shield', 'Aegis Shield', 'aegis_shield', 'Menahan satu serangan'),
  PowerUp('nova', 'Nova Bomb', 'nova_bomb', 'Bersihkan musuh kecil'),
  PowerUp('boots', 'Pegasus Boots', 'pegasus_boots', 'Gerak & lompat meningkat · 10 dtk'),
];

class Buff {
  final String id, name, icon;
  final int max;
  final List<String> description;
  const Buff(this.id, this.name, this.icon, this.max, this.description);
}

const buffs = [
  Buff('split', 'Split Shot', 'split_shot', 2, ['Tembakan membelah menjadi 3', 'Tembakan membelah menjadi 5']),
  Buff('piercing', 'Piercing Ammo', 'piercing_ammo', 3, ['Menembus +1 target', 'Menembus +2 target', 'Menembus +3 target']),
  Buff('fire', 'Fire Bullets', 'fire_bullets', 2, ['Membakar musuh', 'Burn lebih kuat dan meledak']),
  Buff('ice', 'Ice Bullets', 'ice_bullets', 2, ['Memperlambat musuh', 'Slow lebih kuat']),
  Buff('lightning', 'Lightning Bullets', 'lightning_bullets', 2, ['Menyambar 1 target', 'Menyambar 2 target']),
  Buff('vampiric', 'Vampiric Chamber', 'vampiric_chamber', 1, ['50 kill memulihkan 1 HP']),
  Buff('heavy', 'Heavy Caliber', 'heavy_caliber', 2, ['+50% damage, fire rate turun', '+100% damage, peluru lebih besar']),
];

Map<String, int> makeBuffState() => {for (final b in buffs) b.id: 0};

List<Buff> pickBuffChoices(Map<String, int> levels, [int count = 3]) {
  final available = buffs.where((b) => (levels[b.id] ?? 0) < b.max).toList();
  final pool = available.isNotEmpty ? available : [...buffs];
  pool.shuffle(Random());
  return pool.take(count).toList();
}

/// Tweakable balance values (defaults from tweaks.json).
class Balance {
  double playerSpeed = 265;
  double jumpPower = 485;
  double gravity = 1120;
  double fireInterval = 0.2;
  double spawnInterval = 1.15;
  double waveDuration = 95;
  double enemySpeed = 96;
  double bossHealthScale = 1;
  double effectsIntensity = 1;
  double musicVolume = 0.22;
}
