"""Continuous trip segments for multi-store and mixed plans."""
def:pub StoreItinerary(route: dict) -> JsxElement {
    return <section aria-label="Continuous shopping itinerary">
        <h5>Visit order and return</h5>
        {[<details key={str(index)} open>
            <summary>{str(index+1)+'. '+segment['from']+' → '+segment['to']+' · '+str(segment['minutes'])+' min'}</summary>
            <p>{segment['departure_at']+' → '+segment['arrival_at']}</p>
            <ol className="transit-legs">{[<li key={str(i)}>
                <span className="transit-kind">{leg['kind']}</span>
                <div><strong>{('Bus '+leg['route']+' toward '+leg['headsign']) if leg['kind']=='BUS' else leg['from']+' → '+leg['to']}</strong>
                    <p>{leg['departure_at']+' → '+leg['arrival_at']+' · '+str(leg['minutes'])+' min'}</p>
                    {if leg['kind']=='BUS' { <p>{'Stops '+leg['from_stop_code']+' → '+leg['to_stop_code']}</p> }}
                    <small>{leg['source']}</small>
                </div>
            </li> for (i,leg) in enumerate(segment.get('legs',[]))]}</ol>
        </details> for (index,segment) in enumerate(route['segments'])]}
        {[<p key={stop['store_id']}>{stop['name']+': shop '+stop['shopping_at']+' → '+stop['leave_at']+' · Waiting '+str(stop['wait_min'])+' min · Hours '+('recorded' if stop['hours_known'] else 'Unknown')}</p> for stop in route['stops']]}
        <p>{route['notice']}</p>
        {if route.get('feed') { <p>{'TheRide feed '+route['feed']['version']+' · Downloaded '+route['feed']['fetched_at']}</p> }}
    </section>;
}
