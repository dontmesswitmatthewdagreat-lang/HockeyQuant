"""
HockeyQuant Constants
All team data, mappings, and configuration values
"""

# Team timezone offsets from UTC
TEAM_TIMEZONES = {
    'VAN': -8, 'SEA': -8, 'LAK': -8, 'ANA': -8, 'SJS': -8,
    'CGY': -7, 'EDM': -7, 'COL': -7, 'UTA': -7,
    'DAL': -6, 'MIN': -6, 'WPG': -6, 'CHI': -6, 'STL': -6, 'NSH': -6,
    'TOR': -5, 'BOS': -5, 'BUF': -5, 'DET': -5, 'MTL': -5, 'OTT': -5,
    'NYR': -5, 'NYI': -5, 'NJD': -5, 'PHI': -5, 'PIT': -5, 'WSH': -5,
    'CAR': -5, 'CBJ': -5, 'FLA': -5, 'TBL': -5,
}

NHL_DIVISIONS = {
    'Atlantic': ['BOS', 'BUF', 'DET', 'FLA', 'MTL', 'OTT', 'TBL', 'TOR'],
    'Metropolitan': ['CAR', 'CBJ', 'NJD', 'NYI', 'NYR', 'PHI', 'PIT', 'WSH'],
    'Central': ['CHI', 'COL', 'DAL', 'MIN', 'NSH', 'STL', 'WPG', 'UTA'],
    'Pacific': ['ANA', 'CGY', 'EDM', 'LAK', 'SJS', 'SEA', 'VAN', 'VGK'],
}

NHL_CONFERENCES = {
    'Eastern': ['Atlantic', 'Metropolitan'],
    'Western': ['Central', 'Pacific'],
}

# Team name mappings for DailyFaceoff URLs
TEAM_NAMES_DF = {
    'ANA': 'anaheim-ducks', 'BOS': 'boston-bruins', 'BUF': 'buffalo-sabres',
    'CGY': 'calgary-flames', 'CAR': 'carolina-hurricanes', 'CHI': 'chicago-blackhawks',
    'COL': 'colorado-avalanche', 'CBJ': 'columbus-blue-jackets', 'DAL': 'dallas-stars',
    'DET': 'detroit-red-wings', 'EDM': 'edmonton-oilers', 'FLA': 'florida-panthers',
    'LAK': 'los-angeles-kings', 'MIN': 'minnesota-wild', 'MTL': 'montreal-canadiens',
    'NSH': 'nashville-predators', 'NJD': 'new-jersey-devils', 'NYI': 'new-york-islanders',
    'NYR': 'new-york-rangers', 'OTT': 'ottawa-senators', 'PHI': 'philadelphia-flyers',
    'PIT': 'pittsburgh-penguins', 'SJS': 'san-jose-sharks', 'SEA': 'seattle-kraken',
    'STL': 'st-louis-blues', 'TBL': 'tampa-bay-lightning', 'TOR': 'toronto-maple-leafs',
    'UTA': 'utah-hockey-club', 'VAN': 'vancouver-canucks', 'VGK': 'vegas-golden-knights',
    'WSH': 'washington-capitals', 'WPG': 'winnipeg-jets',
}

# ESPN team name to abbreviation mapping
ESPN_TEAM_MAPPING = {
    'Anaheim Ducks': 'ANA', 'Boston Bruins': 'BOS', 'Buffalo Sabres': 'BUF',
    'Calgary Flames': 'CGY', 'Carolina Hurricanes': 'CAR', 'Chicago Blackhawks': 'CHI',
    'Colorado Avalanche': 'COL', 'Columbus Blue Jackets': 'CBJ', 'Dallas Stars': 'DAL',
    'Detroit Red Wings': 'DET', 'Edmonton Oilers': 'EDM', 'Florida Panthers': 'FLA',
    'Los Angeles Kings': 'LAK', 'Minnesota Wild': 'MIN', 'Montreal Canadiens': 'MTL',
    'Nashville Predators': 'NSH', 'New Jersey Devils': 'NJD', 'New York Islanders': 'NYI',
    'New York Rangers': 'NYR', 'Ottawa Senators': 'OTT', 'Philadelphia Flyers': 'PHI',
    'Pittsburgh Penguins': 'PIT', 'San Jose Sharks': 'SJS', 'Seattle Kraken': 'SEA',
    'St. Louis Blues': 'STL', 'Tampa Bay Lightning': 'TBL', 'Toronto Maple Leafs': 'TOR',
    'Utah Hockey Club': 'UTA', 'Vancouver Canucks': 'VAN', 'Vegas Golden Knights': 'VGK',
    'Washington Capitals': 'WSH', 'Winnipeg Jets': 'WPG',
}

# Full team names
TEAM_FULL_NAMES = {v: k for k, v in ESPN_TEAM_MAPPING.items()}

# All team abbreviations
ALL_TEAMS = list(TEAM_TIMEZONES.keys())
