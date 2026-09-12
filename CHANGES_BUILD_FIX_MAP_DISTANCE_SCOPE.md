# Windows build fix — map candidate distance and local scope

- Replaced the four `Math.Hypot` calls in `MainWindow.xaml.cs` with a local `Distance2D(x, y)` helper implemented with `Math.Sqrt((x * x) + (y * y))`, which is available on the current Windows target.
- Renamed the surface/cross-section local bounds in `MapSpawnerContainsPoint` so C# local-variable scope rules no longer reject the repeated `left/right/top/bottom` names.
- No behavior change: candidate hit radii and spawner hit testing use the same Euclidean distance/bounds as before.
