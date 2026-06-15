#!/usr/bin/env python3
import sys
import urllib.request
import urllib.parse
import json

def geocode(location):
    params = {
        'q': location,
        'format': 'json',
        'limit': 1
    }
    url = 'https://nominatim.openstreetmap.org/search?' + urllib.parse.urlencode(params)
    req = urllib.request.Request(
        url,
        headers={'User-Agent': 'QuickshellAI/1.0'}
    )
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            if data:
                return float(data[0]['lon']), float(data[0]['lat']), data[0]['display_name']
    except Exception as e:
        print(f"Geocoding error for '{location}': {e}", file=sys.stderr)
    return None

def main():
    if len(sys.argv) < 3:
        print("Error: Missing origin and/or destination arguments.")
        sys.exit(1)

    origin = sys.argv[1]
    destination = sys.argv[2]
    mode = sys.argv[3] if len(sys.argv) > 3 else "driving"

    # Map requested modes to OSRM profiles
    # OSRM profiles: driving, walking, cycling
    osrm_mode = "driving"
    if mode == "walking":
        osrm_mode = "foot"
    elif mode == "cycling":
        osrm_mode = "bicycle"

    print(f"Geocoding origin: {origin}...")
    origin_res = geocode(origin)
    if not origin_res:
        print(f"Error: Could not geocode origin: '{origin}'")
        sys.exit(1)

    print(f"Geocoding destination: {destination}...")
    dest_res = geocode(destination)
    if not dest_res:
        print(f"Error: Could not geocode destination: '{destination}'")
        sys.exit(1)

    lon1, lat1, name1 = origin_res
    lon2, lat2, name2 = dest_res

    print(f"Origin: {name1} ({lat1}, {lon1})")
    print(f"Destination: {name2} ({lat2}, {lon2})")
    print(f"Mode: {mode}\n")

    profile = "driving"
    if mode == "walking":
        profile = "walking"
    elif mode == "cycling":
        profile = "cycling"

    url = f"http://router.project-osrm.org/route/v1/{profile}/{lon1},{lat1};{lon2},{lat2}?overview=false&steps=true"
    req = urllib.request.Request(
        url,
        headers={'User-Agent': 'QuickshellAI/1.0'}
    )

    try:
        with urllib.request.urlopen(req) as response:
            res_data = json.loads(response.read().decode('utf-8'))
            if res_data.get('code') != 'Ok':
                print(f"Routing error: {res_data.get('message', 'Unknown error')}")
                sys.exit(1)

            route = res_data['routes'][0]
            distance = route['distance'] # in meters
            duration = route['duration'] # in seconds

            print(f"--- Route Summary ---")
            print(f"Distance: {distance/1000:.2f} km")
            print(f"Travel Time: {duration/60:.1f} mins\n")

            print("--- Step-by-Step Directions ---")
            legs = route.get('legs', [])
            step_count = 1
            for leg in legs:
                steps = leg.get('steps', [])
                for step in steps:
                    name = step.get('name', 'unnamed road')
                    instruction = step.get('maneuver', {}).get('type', '')
                    modifier = step.get('maneuver', {}).get('modifier', '')
                    step_dist = step.get('distance', 0)
                    
                    instr_str = f"{instruction} {modifier}".strip().replace("_", " ")
                    if not instr_str:
                        instr_str = "continue"

                    road_str = f"on {name}" if name else ""
                    dist_str = f"for {step_dist:.0f}m" if step_dist > 0 else ""

                    print(f"{step_count}. {instr_str.capitalize()} {road_str} {dist_str}".strip())
                    step_count += 1

    except Exception as e:
        print(f"Error querying routing API: {e}")

if __name__ == "__main__":
    main()
