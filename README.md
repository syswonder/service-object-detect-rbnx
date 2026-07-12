# service-object-detect-rbnx

Robonix package for **LLM/VLM-based object detection**. Atlas + ROS dual surface, drop-in replacement for the older `yolo_world_rbnx`. Owns the `service/perception/object_detect/*` namespace.

Catalog name: `robonix.service.object_detect`.

## Capability surface

| Contract                                                  | Mode | Transport | Source / handler                                          |
| --------------------------------------------------------- | ---- | --------- | --------------------------------------------------------- |
| `robonix/service/perception/object_detect/driver`         | rpc  | gRPC      | `Driver(CMD_INIT, config_json)` — lifecycle gate          |
| `robonix/service/perception/object_detect/detect_object`  | rpc  | gRPC/MCP  | `DetectObject(object_name) → bbox_2d + object_center_3d`  |

The legacy ROS service `/yolo/detect_object` is kept alive as a secondary surface for legacy consumers; the atlas-routed MCP form is the LLM-facing surface.

## Compared with the old `yolo_world` path

- no GPU / ultralytics weights;
- RGB → OpenAI-compatible VLM → 2D bbox;
- in vertical-grasp mode the depth stream is completely unused (`skip_depth=true`); the grasp point is recovered by `service-grasp-pose-rbnx` from a fixed tabletop z plus camera-ray back-projection.

## Boot ordering

Must come **after** `primitive-orbbec-dabai_dcw-camera-rbnx` in the deploy manifest — Init resolves the RGB topic (and, when `skip_depth=false`, the depth topic) at atlas-registration time.

## Driver-init lifecycle

`start.sh` brings up the atlas bridge — no ROS spawn. The bridge opens a gRPC server, registers the capability and declares only `object_detect/driver`, then blocks awaiting `Driver(CMD_INIT, config_json)`.

When `rbnx boot` invokes Init the handler:

1. validates the LLM endpoint / API key / model name;
2. resolves `primitive/camera/rgb` and `primitive/camera/camera_info` via atlas (depth is skipped when `skip_depth=true`);
3. declares `object_detect/detect_object` on atlas.

## Layout

```
service-object-detect-rbnx/
├── package_manifest.yaml
├── capabilities/
│   └── service/perception/object_detect/{driver,detect_object}.v1.toml
├── config/                     example .env / prompt templates
├── llm_detect/                 Python package: atlas bridge + VLM client
├── scripts/
│   ├── build.sh                colcon build + rbnx codegen
│   └── start.sh                source ROS, exec atlas_bridge
└── src/                        vendored dependencies (if any)
```

## Config (passed via `Driver(CMD_INIT, config_json)`)

```json
{
  "llm_base_url":       "https://api.ofox.ai/v1",
  "llm_api_key":        "sk-...",
  "llm_model":          "google/gemini-3.1-flash-lite",
  "temperature":        0.7,
  "rotation_cam2arm":   true,
  "skip_depth":         true,
  "rgb_topic":          "",
  "camera_info_topic":  ""
}
```

- `rotation_cam2arm`: rotate the image 180° before sending to the LLM when the camera is mounted opposite to the arm.
- `skip_depth`: vertical-grasp mode — bypass depth back-projection entirely. `env LLM_DETECT_SKIP_DEPTH=1` is the fallback.
- Empty topic strings mean "atlas-resolved"; defaults already match `primitive-orbbec-dabai_dcw-camera-rbnx`.

## Build / run standalone

```bash
bash scripts/build.sh                           # colcon + rbnx codegen
ROBONIX_ATLAS=127.0.0.1:50051 \
    bash scripts/start.sh                       # registers, awaits Init
```

## Verification

```bash
rbnx caps | grep object_detect
# Expected: llm_detect provider with
#   robonix/service/perception/object_detect/{driver, detect_object}

# End-to-end via the atlas MCP surface:
rbnx ask "where is the paper on the desk?"

# Legacy ROS surface (for backwards compatibility):
ros2 service call /yolo/detect_object <detect_srv_type> \
    "{object_name: 'paper'}"
```

## License

This package: MulanPSL-2.0.
