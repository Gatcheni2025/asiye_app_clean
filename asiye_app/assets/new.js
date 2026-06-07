function drawSmoothRoute(start, end) {
    const url = `https://api.mapbox.com/directions/v5/mapbox/driving/${start[0]},${start[1]};${end[0]},${end[1]}?geometries=geojson&access_token=${mapboxgl.accessToken}`;

    fetch(url)
        .then(response => response.json())
        .then(data => {
            const route = data.routes[0].geometry.coordinates;
            
            // Add route to map with smooth styling
            map.addSource('route', {
                'type': 'geojson',
                'data': {
                    'type': 'Feature',
                    'properties': {},
                    'geometry': { 'type': 'LineString', 'coordinates': route }
                }
            });

            map.addLayer({
                'id': 'route',
                'type': 'line',
                'source': 'route',
                'layout': { 'line-join': 'round', 'line-cap': 'round' },
                'paint': {
                    'line-color': '#276EF1', // Uber Blue
                    'line-width': 6,
                    'line-opacity': 0.8
                }
            });

            // Smoothly fly to the route
            const bounds = new mapboxgl.LngLatBounds(route[0], route[0]);
            for (const coord of route) { bounds.extend(coord); }
            map.fitBounds(bounds, { padding: 100, duration: 2000 });
        });
}