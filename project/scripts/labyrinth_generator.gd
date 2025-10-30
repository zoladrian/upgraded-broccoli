class_name LabyrinthGenerator
extends RefCounted

const DIRECTIONS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]

func generate(cell_counts: Vector2i, tasks: Array, seed: int = 0) -> Dictionary:
    var maze_width := max(2, cell_counts.x)
    var maze_height := max(2, cell_counts.y)
    var rng := RandomNumberGenerator.new()
    if seed != 0:
        rng.seed = seed
    else:
        rng.randomize()

    var grid_size := Vector2i(maze_width * 2 + 1, maze_height * 2 + 1)
    var grid := _create_grid(grid_size)
    var start := Vector2i(1, 1)
    var goal := Vector2i(grid_size.x - 2, grid_size.y - 2)
    _carve_maze(grid, start, rng)
    _ensure_goal_reachable(grid, goal)

    var path := _build_solution_path(grid, start, goal)
    var checkpoints := _create_checkpoints(path, tasks)

    return {
        "grid": grid,
        "path": path,
        "checkpoints": checkpoints,
        "start": start,
        "goal": goal,
    }

func _create_grid(size: Vector2i) -> Array:
    var grid := []
    for y in size.y:
        var row := []
        for x in size.x:
            row.append(false)
        grid.append(row)
    return grid

func _carve_maze(grid: Array, start: Vector2i, rng: RandomNumberGenerator) -> void:
    var stack: Array[Vector2i] = [start]
    grid[start.y][start.x] = true
    var visited := {start: true}

    while not stack.is_empty():
        var current := stack.back()
        var neighbors: Array[Vector2i] = []
        for direction in DIRECTIONS:
            var next_cell := current + direction * 2
            if _is_inside(grid, next_cell) and not visited.has(next_cell):
                neighbors.append(direction)
        if neighbors.is_empty():
            stack.pop_back()
            continue
        var chosen := neighbors[rng.randi_range(0, neighbors.size() - 1)]
        var between := current + chosen
        var destination := current + chosen * 2
        grid[between.y][between.x] = true
        grid[destination.y][destination.x] = true
        visited[destination] = true
        stack.append(destination)

func _ensure_goal_reachable(grid: Array, goal: Vector2i) -> void:
    if not _is_inside(grid, goal):
        return
    grid[goal.y][goal.x] = true
    for direction in DIRECTIONS:
        var neighbor := goal + direction
        if _is_inside(grid, neighbor):
            grid[neighbor.y][neighbor.x] = true

func _build_solution_path(grid: Array, start: Vector2i, goal: Vector2i) -> Array:
    var queue: Array[Vector2i] = [start]
    var came_from := {start: null}
    while not queue.is_empty():
        var current := queue.pop_front()
        if current == goal:
            break
        for direction in DIRECTIONS:
            var next_cell := current + direction
            if _is_inside(grid, next_cell) and grid[next_cell.y][next_cell.x] and not came_from.has(next_cell):
                came_from[next_cell] = current
                queue.append(next_cell)

    var path: Array[Vector2i] = []
    if not came_from.has(goal):
        # fallback to start only if goal unreachable
        path.append(start)
        return path

    var cursor := goal
    while cursor != null:
        path.push_front(cursor)
        cursor = came_from.get(cursor)
    return path

func _create_checkpoints(path: Array, tasks: Array) -> Array:
    var checkpoints: Array = []
    if path.size() <= 1 or tasks.is_empty():
        return checkpoints

    var usable_tasks := tasks.duplicate()
    var step := max(1, int(floor(float(path.size() - 1) / float(usable_tasks.size()))))
    var index := step
    for task_idx in usable_tasks.size():
        if index >= path.size():
            index = path.size() - 1
        var task := usable_tasks[task_idx]
        var repetitions := int(max(1, task.get("repetitions", 1)))
        checkpoints.append({
            "path_index": index,
            "grid_position": path[index],
            "word_id": task.get("word_id", "task_%d" % task_idx),
            "target_text": task.get("text", task.get("word_id", "")),
            "repetitions": repetitions,
            "remaining": repetitions,
            "completed": false,
        })
        index = min(path.size() - 1, index + step)
    return checkpoints

func _is_inside(grid: Array, cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.y >= 0 and cell.y < grid.size() and cell.x < grid[cell.y].size()
