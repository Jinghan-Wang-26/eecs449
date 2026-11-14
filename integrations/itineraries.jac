"""Fetch directional road evidence; Jac schedules the resulting continuous trip."""
import from itertools { permutations }
import from integrations.providers { route, ProviderError }
import from planning.itineraries { road_itinerary, bus_itinerary }
def itinerary_options(
    stores: any, context: any, now: any, delivery: any = None
) -> any {
    (options, errors) = ([], []);
    for order in permutations(stores) {
        for mode in context['profile']['transport'] {
            try {
                if (mode == 'BUS') {
                    result = bus_itinerary(`list(order), context, now, delivery);
                } elif (mode in ('WALK', 'BIKE', 'CAR')) {
                    points = [context['origin'], *order, context['origin']];
                    links = [];
                    for (a, b) in zip(points, points[1:]) {
                        value = route([a['lat'], a['lon']], [b['lat'], b['lon']], mode);
                        links.append(
                            {
                                'minutes': value['outbound_min'],
                                'valid_until': value['valid_until']
                            }
                        );
                    }
                    result = road_itinerary(
                        `list(order), links, mode, context, now, delivery
                    );
                } else {
                    continue;
                }
                options.append((`list(order), result));
            } except ProviderError as error {
                errors.append((mode + ': ' + str(error)));
            }
        }
    }
    return (options, `list(`dict.fromkeys(errors)));
}
