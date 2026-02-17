/**
 * NHL Team Logo Utilities
 * Uses official NHL CDN for team logos
 */

// NHL CDN base URL for team logos
const NHL_LOGO_CDN = 'https://assets.nhle.com/logos/nhl/svg';

/**
 * Get the logo URL for a team
 * @param {string} abbrev - Team abbreviation (e.g., "TOR", "BOS")
 * @param {string} variant - Logo variant: "light" (default) or "dark"
 * @returns {string} - URL to the team's SVG logo
 */
export const getTeamLogo = (abbrev, variant = 'light') => {
  if (!abbrev) return '';
  return `${NHL_LOGO_CDN}/${abbrev}_${variant}.svg`;
};

/**
 * Get the dark variant logo for a team
 * @param {string} abbrev - Team abbreviation
 * @returns {string} - URL to the team's dark SVG logo
 */
export const getTeamLogoDark = (abbrev) => {
  return getTeamLogo(abbrev, 'dark');
};

/**
 * Team full names mapping
 */
export const TEAM_NAMES = {
  ANA: 'Anaheim Ducks',
  ARI: 'Arizona Coyotes',
  BOS: 'Boston Bruins',
  BUF: 'Buffalo Sabres',
  CGY: 'Calgary Flames',
  CAR: 'Carolina Hurricanes',
  CHI: 'Chicago Blackhawks',
  COL: 'Colorado Avalanche',
  CBJ: 'Columbus Blue Jackets',
  DAL: 'Dallas Stars',
  DET: 'Detroit Red Wings',
  EDM: 'Edmonton Oilers',
  FLA: 'Florida Panthers',
  LAK: 'Los Angeles Kings',
  MIN: 'Minnesota Wild',
  MTL: 'Montreal Canadiens',
  NSH: 'Nashville Predators',
  NJD: 'New Jersey Devils',
  NYI: 'New York Islanders',
  NYR: 'New York Rangers',
  OTT: 'Ottawa Senators',
  PHI: 'Philadelphia Flyers',
  PIT: 'Pittsburgh Penguins',
  SJS: 'San Jose Sharks',
  SEA: 'Seattle Kraken',
  STL: 'St. Louis Blues',
  TBL: 'Tampa Bay Lightning',
  TOR: 'Toronto Maple Leafs',
  UTA: 'Utah Mammoth',
  VAN: 'Vancouver Canucks',
  VGK: 'Vegas Golden Knights',
  WSH: 'Washington Capitals',
  WPG: 'Winnipeg Jets',
};

/**
 * Get the full team name from abbreviation
 * @param {string} abbrev - Team abbreviation
 * @returns {string} - Full team name
 */
export const getTeamName = (abbrev) => {
  return TEAM_NAMES[abbrev] || abbrev;
};

/**
 * Team primary colors (for styling)
 */
export const TEAM_COLORS = {
  ANA: '#F47A38',
  ARI: '#8C2633',
  BOS: '#FFB81C',
  BUF: '#002654',
  CGY: '#D2001C',
  CAR: '#CC0000',
  CHI: '#CF0A2C',
  COL: '#6F263D',
  CBJ: '#002654',
  DAL: '#006847',
  DET: '#CE1126',
  EDM: '#041E42',
  FLA: '#041E42',
  LAK: '#111111',
  MIN: '#154734',
  MTL: '#AF1E2D',
  NSH: '#FFB81C',
  NJD: '#CE1126',
  NYI: '#00539B',
  NYR: '#0038A8',
  OTT: '#C52032',
  PHI: '#F74902',
  PIT: '#FCB514',
  SJS: '#006D75',
  SEA: '#001628',
  STL: '#002F87',
  TBL: '#002868',
  TOR: '#00205B',
  UTA: '#6CACE4',
  VAN: '#00205B',
  VGK: '#B4975A',
  WSH: '#041E42',
  WPG: '#041E42',
};

/**
 * Get the primary color for a team
 * @param {string} abbrev - Team abbreviation
 * @returns {string} - Hex color code
 */
export const getTeamColor = (abbrev) => {
  return TEAM_COLORS[abbrev] || '#333333';
};

export default {
  getTeamLogo,
  getTeamLogoDark,
  getTeamName,
  getTeamColor,
  TEAM_NAMES,
  TEAM_COLORS,
};
