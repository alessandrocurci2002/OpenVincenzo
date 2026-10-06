"""Rotation helpers for the OpenVINS -> PX4 VehicleOdometry conversion.

Quaternions are Hamilton, stored as numpy arrays [w, x, y, z] (PX4 order).
Rotation matrices R map a vector expressed in the "from" frame to its
components in the "to" frame: v_to = R @ v_from.
"""

import numpy as np

# OpenVINS "global" world frame (gravity-aligned, z-up, arbitrary heading)
# -> PX4 POSE_FRAME_FRD / VELOCITY_FRAME_FRD world frame (z-down, same heading).
# Fixed by the message convention itself, not a calibration value: a 180 deg
# rotation about the (shared) forward/x axis.
WORLD_ROTATION_MATRIX = np.diag([1.0, -1.0, -1.0])
WORLD_ROTATION_QUAT = np.array([0.0, 1.0, 0.0, 0.0])  # w,x,y,z


def rotation_matrix_from_euler_deg(roll_deg: float, pitch_deg: float, yaw_deg: float) -> np.ndarray:
    """Aerospace ZYX rotation matrix (R = Rz(yaw) @ Ry(pitch) @ Rx(roll))."""
    r, p, y = np.radians([roll_deg, pitch_deg, yaw_deg])
    cr, sr = np.cos(r), np.sin(r)
    cp, sp = np.cos(p), np.sin(p)
    cy, sy = np.cos(y), np.sin(y)
    rx = np.array([[1, 0, 0], [0, cr, -sr], [0, sr, cr]])
    ry = np.array([[cp, 0, sp], [0, 1, 0], [-sp, 0, cp]])
    rz = np.array([[cy, -sy, 0], [sy, cy, 0], [0, 0, 1]])
    return rz @ ry @ rx


def quat_from_rotation_matrix(r: np.ndarray) -> np.ndarray:
    """Hamilton [w,x,y,z] quaternion equivalent to rotation matrix r."""
    trace = np.trace(r)
    if trace > 0:
        s = np.sqrt(trace + 1.0) * 2
        w = 0.25 * s
        x = (r[2, 1] - r[1, 2]) / s
        y = (r[0, 2] - r[2, 0]) / s
        z = (r[1, 0] - r[0, 1]) / s
    elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
        s = np.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2]) * 2
        w = (r[2, 1] - r[1, 2]) / s
        x = 0.25 * s
        y = (r[0, 1] + r[1, 0]) / s
        z = (r[0, 2] + r[2, 0]) / s
    elif r[1, 1] > r[2, 2]:
        s = np.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2]) * 2
        w = (r[0, 2] - r[2, 0]) / s
        x = (r[0, 1] + r[1, 0]) / s
        y = 0.25 * s
        z = (r[1, 2] + r[2, 1]) / s
    else:
        s = np.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1]) * 2
        w = (r[1, 0] - r[0, 1]) / s
        x = (r[0, 2] + r[2, 0]) / s
        y = (r[1, 2] + r[2, 1]) / s
        z = 0.25 * s
    return np.array([w, x, y, z])


def quat_conjugate(q: np.ndarray) -> np.ndarray:
    w, x, y, z = q
    return np.array([w, -x, -y, -z])


def quat_multiply(q1: np.ndarray, q2: np.ndarray) -> np.ndarray:
    w1, x1, y1, z1 = q1
    w2, x2, y2, z2 = q2
    return np.array(
        [
            w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2,
            w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
            w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
            w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
        ]
    )


def quat_normalize(q: np.ndarray) -> np.ndarray:
    return q / np.linalg.norm(q)


def rotate_covariance(cov3x3: np.ndarray, r: np.ndarray) -> np.ndarray:
    """Propagate a 3x3 covariance block through a fixed rotation r."""
    return r @ cov3x3 @ r.T
