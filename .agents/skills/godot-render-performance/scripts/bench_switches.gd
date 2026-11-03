extends Node
## Per-feature frame-cost bench for Godot 4.x: measures what each visual "switch" costs at a FIXED view.
## Checked against Godot 4.7.2.stable (RenderingServer.viewport_set_measure_render_time /
## viewport_get_measured_render_time_gpu / viewport_get_measured_render_time_cpu).
##
## Usage: add this node to the scene (camera already placed), then:
##   var bench := preload("res://tools/bench_switches.gd").new()
##   add_child(bench)
##   var results := await bench.run({
##       "sun_shadows": func(on): $Sun.shadow_enabled = on,
##       "ssao":        func(on): env.ssao_enabled = on,
##       "sdfgi":       func(on): env.sdfgi_enabled = on,
##       "grass":       func(on): $Grass.visible = on,
##   }, {"frames": 300, "warmup": 60})
## Every toggle is a Callable(on: bool) that must be reversible (on -> off -> on gives the same scene).
##
## It measures four things, in this order:
##   all_off, all_on,
##   "alone:<name>"  = only that switch on (cost of the feature on a light scene),
##   "minus:<name>"  = everything on except that switch (what you SAVE by removing it from the full scene;
##                     this is the test that finds the expensive switch).
## Reported per configuration: GPU ms (what the graphics card spends), CPU render ms, and wall frame ms.
## Run with vsync off and no FPS cap (`--max-fps 0`, project display/window/vsync/vsync_mode = Disabled),
## otherwise every result is the monitor's refresh interval.

signal finished(results: Dictionary)


func run(toggles: Dictionary, o := {}) -> Dictionary:
	var frames := int(o.get("frames", 300))
	var warmup := int(o.get("warmup", 60))
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var names: Array = toggles.keys()
	var results := {}

	var configs: Array = [["all_off", []], ["all_on", names.duplicate()]]
	for n in names:
		configs.append(["alone:" + n, [n]])
	for n in names:
		var others := names.duplicate()
		others.erase(n)
		configs.append(["minus:" + n, others])

	for cfg in configs:
		for n in names:
			(toggles[n] as Callable).call(n in cfg[1])
		results[cfg[0]] = await _measure(vp_rid, frames, warmup)

	print(format_table(results, names))
	finished.emit(results)
	return results


func _measure(vp_rid: RID, frames: int, warmup: int) -> Dictionary:
	for i in warmup:   # let SDFGI/TAA/shader compilation settle after a toggle
		await RenderingServer.frame_post_draw
	var gpu := 0.0
	var cpu := 0.0
	var wall: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		wall.append((now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
	wall.sort()
	var sum := 0.0
	for t in wall:
		sum += t
	return {
		"gpu_ms": snappedf(gpu / frames, 0.001),
		"cpu_render_ms": snappedf(cpu / frames, 0.001),
		"frame_ms": snappedf(sum / frames, 0.001),
		"frame_p95_ms": snappedf(wall[min(frames - 1, int(frames * 0.95))], 0.001),
		"fps": snappedf(1000.0 * frames / sum, 0.1),
	}


static func format_table(results: Dictionary, names: Array) -> String:
	var on: Dictionary = results.get("all_on", {})
	var off: Dictionary = results.get("all_off", {})
	var lines := ["| config | GPU ms | frame ms | p95 ms | fps | GPU saved vs all_on |", "|---|---|---|---|---|---|"]
	for k in results:
		var r: Dictionary = results[k]
		var saved := ""
		if str(k).begins_with("minus:") and on.has("gpu_ms"):
			saved = "%.3f" % (on.gpu_ms - r.gpu_ms)
		lines.append("| %s | %.3f | %.3f | %.3f | %.1f | %s |" % [k, r.gpu_ms, r.frame_ms, r.frame_p95_ms, r.fps, saved])
	if on.has("gpu_ms") and off.has("gpu_ms"):
		lines.append("")
		lines.append("all_on - all_off = %.3f GPU ms" % (on.gpu_ms - off.gpu_ms))
	return "\n".join(lines)
