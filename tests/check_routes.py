"""Detection — write the check once and let it run forever"""



def find_shadowed(app):
    """A later route is unreachable if an EARLIER route's pattern already matches it."""
    problems = []
    routes = [r for r in app.routes if hasattr(r, "path_regex")]
    for i, route in enumerate(routes):
        if "{" in route.path:          # only literal paths can be shadowed
            continue
        for earlier in routes[:i]:
            if earlier.path_regex.match(route.path) and earlier.methods & route.methods:
                problems.append((route.path, earlier.path))
                break
    return problems


if __name__ == "__main__" :
    from main import app
    problems = find_shadowed(app)
    if problems:
        for route_path, earlier_path in problems:
            print(f"UNREACHABLE  {route_path}   ← captured by {earlier_path}")
    else:
        print("No shadowed routes found.")
