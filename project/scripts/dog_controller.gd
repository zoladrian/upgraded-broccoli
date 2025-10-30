class_name DogController
extends CharacterBody2D

signal path_completed

@export var move_speed := 120.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _state_machine: AnimationNodeStateMachinePlayback
var _path: Array[Vector2] = []
var _current_point := 0
var _target_reached := true

func _ready() -> void:
    _ensure_animations()
    _ensure_state_machine()
    animation_tree.active = true
    play_idle()

func follow_path(points: Array[Vector2]) -> void:
    _path = points.duplicate()
    _current_point = 0
    if _path.is_empty():
        play_idle()
        emit_signal("path_completed")
        return
    _target_reached = false
    play_walk()

func clear_path() -> void:
    _path.clear()
    _target_reached = true
    velocity = Vector2.ZERO
    move_and_slide()
    play_idle()

func _physics_process(delta: float) -> void:
    if _path.is_empty():
        if not _target_reached:
            _target_reached = true
            velocity = Vector2.ZERO
            move_and_slide()
            play_idle()
            emit_signal("path_completed")
        return

    var target := _path[_current_point]
    var to_target := target - global_position
    if to_target.length() <= 4.0:
        _current_point += 1
        if _current_point >= _path.size():
            _path.clear()
            velocity = Vector2.ZERO
            move_and_slide()
            play_idle()
            _target_reached = true
            emit_signal("path_completed")
            return
        target = _path[_current_point]
        to_target = target - global_position

    if to_target != Vector2.ZERO:
        velocity = to_target.normalized() * move_speed
        _update_orientation(velocity)
    else:
        velocity = Vector2.ZERO
    move_and_slide()

func play_idle() -> void:
    if _state_machine:
        _state_machine.travel("Idle")

func play_walk() -> void:
    if _state_machine:
        _state_machine.travel("Walk")

func play_sit() -> void:
    if _state_machine:
        _state_machine.travel("Sit")

func play_sit_feedback() -> void:
    clear_path()
    play_sit()
    await animation_player.animation_finished
    play_idle()

func _update_orientation(direction: Vector2) -> void:
    if abs(direction.x) > 0.1:
        sprite.flip_h = direction.x < 0.0

func _ensure_animations() -> void:
    if not animation_player.has_animation("idle"):
        var idle_anim := Animation.new()
        idle_anim.loop_mode = Animation.LOOP_LINEAR
        idle_anim.length = 0.5
        var idle_track := idle_anim.add_track(Animation.TYPE_VALUE)
        idle_anim.track_set_path(idle_track, "Sprite2D:scale")
        idle_anim.track_insert_key(idle_track, 0.0, Vector2.ONE)
        idle_anim.track_insert_key(idle_track, 0.25, Vector2(1.05, 0.95))
        idle_anim.track_insert_key(idle_track, 0.5, Vector2.ONE)
        animation_player.add_animation("idle", idle_anim)

    if not animation_player.has_animation("walk"):
        var walk_anim := Animation.new()
        walk_anim.loop_mode = Animation.LOOP_LINEAR
        walk_anim.length = 0.6
        var walk_track := walk_anim.add_track(Animation.TYPE_VALUE)
        walk_anim.track_set_path(walk_track, "Sprite2D:position")
        walk_anim.track_insert_key(walk_track, 0.0, Vector2.ZERO)
        walk_anim.track_insert_key(walk_track, 0.3, Vector2(0, -4))
        walk_anim.track_insert_key(walk_track, 0.6, Vector2.ZERO)
        animation_player.add_animation("walk", walk_anim)

    if not animation_player.has_animation("sit"):
        var sit_anim := Animation.new()
        sit_anim.loop_mode = Animation.LOOP_NONE
        sit_anim.length = 0.7
        var sit_rot := sit_anim.add_track(Animation.TYPE_VALUE)
        sit_anim.track_set_path(sit_rot, "Sprite2D:rotation_degrees")
        sit_anim.track_insert_key(sit_rot, 0.0, 0.0)
        sit_anim.track_insert_key(sit_rot, 0.35, -30.0)
        sit_anim.track_insert_key(sit_rot, 0.7, -30.0)
        var sit_pos := sit_anim.add_track(Animation.TYPE_VALUE)
        sit_anim.track_set_path(sit_pos, "Sprite2D:position")
        sit_anim.track_insert_key(sit_pos, 0.0, Vector2.ZERO)
        sit_anim.track_insert_key(sit_pos, 0.35, Vector2(0, 4))
        sit_anim.track_insert_key(sit_pos, 0.7, Vector2(0, 4))
        animation_player.add_animation("sit", sit_anim)

func _ensure_state_machine() -> void:
    var state_machine := animation_tree.tree_root
    if not state_machine or not (state_machine is AnimationNodeStateMachine):
        state_machine = AnimationNodeStateMachine.new()
        animation_tree.tree_root = state_machine

    var root_machine := state_machine as AnimationNodeStateMachine
    if not root_machine.has_node("Idle"):
        var idle_node := AnimationNodeAnimation.new()
        idle_node.animation = "idle"
        root_machine.add_node("Idle", idle_node)
    if not root_machine.has_node("Walk"):
        var walk_node := AnimationNodeAnimation.new()
        walk_node.animation = "walk"
        root_machine.add_node("Walk", walk_node)
    if not root_machine.has_node("Sit"):
        var sit_node := AnimationNodeAnimation.new()
        sit_node.animation = "sit"
        root_machine.add_node("Sit", sit_node)

    _ensure_transition(root_machine, "Idle", "Walk")
    _ensure_transition(root_machine, "Walk", "Idle")
    _ensure_transition(root_machine, "Idle", "Sit")
    _ensure_transition(root_machine, "Sit", "Idle")
    _ensure_transition(root_machine, "Walk", "Sit")

    _state_machine = animation_tree.get("parameters/playback")
    if _state_machine:
        _state_machine.start("Idle")

func _ensure_transition(machine: AnimationNodeStateMachine, from: String, to: String) -> void:
    for i in machine.get_transition_count():
        var existing := machine.get_transition(i)
        if existing.from_state == from and existing.to_state == to:
            return
    var transition := AnimationNodeStateMachineTransition.new()
    machine.add_transition(from, to, transition)
