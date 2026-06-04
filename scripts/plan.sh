#!/usr/bin/env bash
# Kontour Travel Planner — Quick Planning Script
# Usage: ./plan.sh "your trip description"
# Outputs structured trip context JSON by extracting dimensions from natural language.
# No API keys or external services required — runs entirely offline.

set -euo pipefail

QUERY="${1:-}"
if [ -z "$QUERY" ]; then
  echo "Usage: $0 \"<trip description>\""
  echo "Example: $0 \"2 weeks in Japan for a couple, mid-range budget, food and temples\""
  exit 1
fi

# Validate input boundary: capped length + strict character allowlist
if [ "${#QUERY}" -gt 280 ]; then
  echo "Error: Query too long (max 280 chars)." >&2
  exit 1
fi
if ! echo "$QUERY" | grep -qE '^[a-zA-Z0-9 ,.\-\/\$€£¥()!?'\''&]+$'; then
  echo "Error: Query contains unsupported characters." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
DEST_FILE="$SKILL_DIR/references/destinations.json"

# All processing done in Python with proper argument passing (no shell interpolation)
python3 - "$QUERY" "$DEST_FILE" << 'PYEOF'
import json, sys, re, os

query = sys.argv[1]
dest_file = sys.argv[2]

def extract_destination(text):
    m = re.search(r'\b(?:in|to|visit|visiting|explore|exploring)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', text)
    if m:
        dest = re.sub(r'\s+[Ff]or$', '', m.group(1))
        return dest
    return ""

def extract_duration(text):
    m = re.search(r'(\d+)\s*(days?|weeks?|nights?)', text, re.IGNORECASE)
    if m:
        num = int(m.group(1))
        if 'week' in m.group(2).lower():
            return num * 7
        return num
    return None

def extract_travelers(text):
    t = text.lower()
    if 'solo' in t: return 1
    if 'couple' in t: return 2
    if 'family' in t: return 4
    m = re.search(r'(\d+)\s*(?:people|travelers|adults|persons)', t)
    if m: return int(m.group(1))
    return None

def extract_budget_tier(text):
    t = text.lower()
    if re.search(r'mid.range|moderate|comfort', t): return "mid"
    if re.search(r'budget|cheap|backpack', t): return "budget"
    if re.search(r'luxury|premium|high.end|splurge', t): return "luxury"
    return ""

def parse_money_amount(raw):
    return int(raw.replace(',', ''))

def extract_budget_cap(text):
    currency_symbols = {'$': 'USD', '€': 'EUR', '£': 'GBP', '¥': 'JPY'}
    cap_patterns = [
        r'\b(?:under|below|less than|max(?:imum)?|cap(?:ped)? at|budget cap|up to)\s*([$€£¥])\s*([0-9][0-9,]*)',
        r'([$€£¥])\s*([0-9][0-9,]*)\s*(?:max|cap|budget|total|for the trip)?',
        r'\b(?:under|below|less than|max(?:imum)?|cap(?:ped)? at|budget cap|up to)\s*([0-9][0-9,]*)\s*(usd|eur|gbp|jpy|dollars?|euros?|pounds?|yen)\b',
    ]
    for pattern in cap_patterns:
        m = re.search(pattern, text, re.IGNORECASE)
        if not m:
            continue
        groups = m.groups()
        if groups[0] in currency_symbols:
            currency = currency_symbols[groups[0]]
            amount = parse_money_amount(groups[1])
        else:
            currency_word = groups[1].lower()
            currency = {'dollar': 'USD', 'dollars': 'USD', 'usd': 'USD', 'euro': 'EUR', 'euros': 'EUR', 'eur': 'EUR', 'pound': 'GBP', 'pounds': 'GBP', 'gbp': 'GBP', 'yen': 'JPY', 'jpy': 'JPY'}.get(currency_word, currency_word.upper())
            amount = parse_money_amount(groups[0])
        scope = 'per_person' if re.search(r'per person|pp|each', text, re.IGNORECASE) else 'total'
        return {'amount': amount, 'currency': currency, 'scope': scope}
    return None

def extract_trip_pace(text):
    t = text.lower()
    if re.search(r'\b(relaxed|slow|easy|leisurely|not rushed)\b', t):
        return 'relaxed'
    if re.search(r'\b(packed|busy|fast-paced|fast paced|see as much|ambitious)\b', t):
        return 'packed'
    if re.search(r'\b(balanced|moderate pace|some downtime)\b', t):
        return 'balanced'
    return None

def extract_neighborhood_preference(text):
    patterns = [
        r'\b(?:near|around|close to|by)\s+([A-Z][A-Za-z0-9 .\-]+?)(?=\s+(?:with|and|for|under|below|less|max|budget|relaxed|packed|balanced|vegetarian|vegan|halal|gluten|avoid|must|rain|heat|cold|$))',
        r'\b(?:stay(?:ing)? in|base(?:d)? in|prefer(?:red)? base in|neighborhood preference:?|neighbourhood preference:?)\s+([A-Z][A-Za-z0-9 .\-]+?)(?=\s+(?:with|and|for|under|below|less|max|budget|relaxed|packed|balanced|vegetarian|vegan|halal|gluten|avoid|must|rain|heat|cold|$))',
    ]
    for pattern in patterns:
        m = re.search(pattern, text)
        if m:
            area = m.group(1).strip(' .,')
            if area:
                return area
    return None

def extract_opening_hours_sensitivity(text):
    t = text.lower()
    signals = []
    if re.search(r'must be open|needs? to be open|open on|opening hours|avoid closed|closed days?', t):
        signals.append('must_verify_open')
    if re.search(r'late night|after dark|evening-only|evening only', t):
        signals.append('late_hours_needed')
    if re.search(r'early morning|sunrise|before 9', t):
        signals.append('early_hours_needed')
    day_match = re.search(r'open on (monday|tuesday|wednesday|thursday|friday|saturday|sunday)', t)
    if day_match:
        signals.append(f"open_on_{day_match.group(1)}")
    return signals

def extract_food_preferences(text):
    preferences = [
        ('vegetarian', r'\bvegetarian\b'),
        ('vegan', r'\bvegan\b'),
        ('halal', r'\bhalal\b'),
        ('kosher', r'\bkosher\b'),
        ('gluten_free', r'gluten[- ]free|celiac|coeliac'),
        ('seafood', r'\bseafood\b'),
        ('street_food', r'street food'),
        ('no_raw_fish', r'no raw fish|avoid raw fish'),
    ]
    t = text.lower()
    return [name for name, pattern in preferences if re.search(pattern, t)]

def extract_weather_sensitivity(text):
    t = text.lower()
    signals = []
    if re.search(r'rain|rainy|wet weather|umbrella', t):
        signals.append('rain_sensitive')
    if re.search(r'indoor backup|rain backup|backup indoors|avoid rainy outdoor', t):
        signals.append('needs_indoor_backup')
    if re.search(r'heat sensitive|avoid heat|too hot|cooler hours', t):
        signals.append('heat_sensitive')
    if re.search(r'cold sensitive|avoid cold|too cold', t):
        signals.append('cold_sensitive')
    if re.search(r'weather dependent|weather-sensitive|weather sensitive', t):
        signals.append('weather_dependent')
    return signals

def extract_constraints(text):
    constraints = {}
    budget_cap = extract_budget_cap(text)
    if budget_cap:
        constraints['budget_cap'] = budget_cap
    pace = extract_trip_pace(text)
    if pace:
        constraints['trip_pace'] = pace
    neighborhood = extract_neighborhood_preference(text)
    if neighborhood:
        constraints['neighborhood_preference'] = neighborhood
    hours = extract_opening_hours_sensitivity(text)
    if hours:
        constraints['opening_hours_sensitivity'] = hours
    food = extract_food_preferences(text)
    if food:
        constraints['food_preference'] = food
    weather = extract_weather_sensitivity(text)
    if weather:
        constraints['weather_sensitivity'] = weather
    return constraints

def extract_interests(text):
    keywords = ['food', 'culinary', 'temple', 'culture', 'history', 'museum', 'art',
                'beach', 'adventure', 'hiking', 'nature', 'nightlife', 'shopping',
                'wellness', 'spa', 'photography', 'architecture', 'wine']
    t = text.lower()
    return [kw for kw in keywords if kw in t]

dest = extract_destination(query)
duration = extract_duration(query)
travelers = extract_travelers(query)
budget_tier = extract_budget_tier(query)
constraints = extract_constraints(query)
interests = extract_interests(query)

ctx = {}

# Look up destination in references
dest_data = None
if dest and os.path.isfile(dest_file):
    with open(dest_file) as f:
        dests = json.load(f)
    dest_lower = dest.lower()
    dest_data = next((d for d in dests if d['name'].lower() == dest_lower or d['country'].lower() == dest_lower), None)

if dest_data:
    ctx['destination'] = {
        'name': dest_data['name'],
        'country': dest_data['country'],
        'coordinates': dest_data['coordinates'],
        'currency': dest_data['currency'],
        'timezone': dest_data['timezone'],
        'avg_daily_cost_usd': dest_data['avg_daily_cost_usd']
    }
elif dest:
    ctx['destination'] = {'name': dest}

if duration:
    ctx['duration_days'] = duration
if travelers:
    ctx['travelers'] = {'adults': travelers}
if budget_tier or constraints.get('budget_cap'):
    ctx['budget'] = {}
    if budget_tier:
        ctx['budget']['tier'] = budget_tier
    if constraints.get('budget_cap'):
        ctx['budget']['cap'] = constraints['budget_cap']
    if dest_data:
        costs = dest_data.get('avg_daily_cost_usd', {})
        if budget_tier:
            daily = costs.get(budget_tier, costs.get('mid'))
            if daily and duration:
                ctx['budget']['estimated_total'] = daily * duration * (travelers or 1)
                ctx['budget']['daily_per_person'] = daily
        cap = constraints.get('budget_cap')
        if cap and cap.get('currency') == 'USD' and duration:
            party_size = travelers or 1
            comparable_cap = cap['amount'] * party_size if cap.get('scope') == 'per_person' else cap['amount']
            tier_totals = {tier: cost * duration * party_size for tier, cost in costs.items()}
            affordable = [tier for tier, total in tier_totals.items() if comparable_cap >= total]
            if affordable:
                best_fit = affordable[-1]
                ctx['budget']['cap_fit'] = {'status': 'fits', 'best_matching_tier': best_fit, 'tier_totals_usd': tier_totals}
            else:
                ctx['budget']['cap_fit'] = {'status': 'tight', 'lowest_tier_total_usd': min(tier_totals.values()) if tier_totals else None, 'tier_totals_usd': tier_totals}
if constraints:
    ctx['constraints'] = constraints
if interests:
    ctx['interests'] = interests

budget_known = bool(budget_tier or constraints.get('budget_cap'))
constraints_known = bool(constraints)
dims_complete = sum(1 for v in [dest, duration, travelers, budget_known, interests, constraints_known] if v)
if dims_complete >= 6:
    ctx['planning_stage'] = 'refine'
elif dims_complete >= 4:
    ctx['planning_stage'] = 'develop'
else:
    ctx['planning_stage'] = 'discover'

ctx['open_decisions'] = []
if not dest: ctx['open_decisions'].append('destination')
if not duration: ctx['open_decisions'].append('dates/duration')
if not travelers: ctx['open_decisions'].append('travelers')
if not budget_known: ctx['open_decisions'].append('budget')
if not interests: ctx['open_decisions'].append('interests')
ctx['open_decisions'].extend(['accommodation', 'transport'])
if not constraints_known: ctx['open_decisions'].append('constraints')

print(json.dumps(ctx, indent=2))
PYEOF
