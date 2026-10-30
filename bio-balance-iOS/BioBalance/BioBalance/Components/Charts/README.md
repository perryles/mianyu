# Charts component module

This directory owns reusable chart implementations and chart-specific analysis code.

- `Core/`: shared chart surfaces, headers, legends, metric pills, selection readouts, and semantic colors.
- `Activity/`: activity trend charts.
- `Health/`: reusable health metric trend containers.
- `Heart/`: heart and cardiovascular charts that are reusable across feature screens.
- `Stress/`: stress and emotion trend charts.
- Feature screens under `Views/` should prepare data and compose chart components, rather than implement marks, gestures, or statistical calculations inline.

When adding a chart, keep pure calculations in a separate analyzer file so they can be unit tested without rendering SwiftUI.
