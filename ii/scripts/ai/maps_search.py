#!/usr/bin/env python3
import sys
import urllib.request
import urllib.parse
import json

def main():
    if len(sys.argv) < 2:
        print("Error: No search query provided.")
        sys.exit(1)

    query = sys.argv[1]
    params = {
        'q': query,
        'format': 'json',
        'limit': 5,
        'addressdetails': 1
    }
    url = 'https://nominatim.openstreetmap.org/search?' + urllib.parse.urlencode(params)

    req = urllib.request.Request(
        url,
        headers={'User-Agent': 'QuickshellAI/1.0'}
    )

    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            if not data:
                print(f"No results found for '{query}'.")
                return

            print(f"Search results for '{query}':\n")
            for idx, item in enumerate(data, 1):
                name = item.get('display_name')
                lat = item.get('lat')
                lon = item.get('lon')
                type_ = item.get('type')
                print(f"{idx}. {name}")
                print(f"   Latitude: {lat}, Longitude: {lon}")
                print(f"   Type: {type_}\n")
    except Exception as e:
        print(f"Error querying maps search API: {e}")

if __name__ == "__main__":
    main()
