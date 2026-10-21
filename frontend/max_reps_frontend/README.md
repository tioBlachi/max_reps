# max_reps_frontend

Flutter frontend for MaxReps.

## Browser navigation

The app uses `go_router` and clean path URLs:

- `/training`: Training Zone
- `/training/add-lift`: Add Lift (optional `?unit=kg`)
- `/profile`: account settings
- `/admin`: admin dashboard
- `/login` and `/register`: authentication

Refreshing a protected URL first validates the saved JWT, then opens that page.
If sign-in is required, a `from` query parameter preserves the destination.
Admin and regular-user pages remain restricted to their respective roles.

Run locally with `flutter run -d chrome --web-port 3000`. Flutter's development
server already supports loading the app from these URLs.

For deployment, configure the frontend web host to serve `index.html` for app
paths such as `/profile` and `/training/add-lift`. Otherwise a direct visit or
refresh can return a web-server 404 before Flutter loads. Serve existing static
assets normally; the FastAPI backend does not need additional routes.

See [Flutter's URL strategy documentation](https://docs.flutter.dev/ui/navigation/url-strategies).
