# Static bottom tabs / dynamic navigation titles fix

- Entity and chunk bottom tab titles remain fixed as `实体` and `区块`.
- Entity page count is now written only to `navigationItem.title`, e.g. `实体（100）` / `方块实体（20）`.
- Chunk page count is now written only to `navigationItem.title`, e.g. `区块（100）`.
- Avoids mutating `UIViewController.title` after the tab is created, preventing UIKit from propagating dynamic counts into the bottom tab title.
- Regression checks now reject dynamic entity/chunk counts written through `UIViewController.title`.
