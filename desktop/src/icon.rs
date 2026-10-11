//! The app/tray icon, drawn in code: a lavender ring with a "Y" on dark plum.

/// RGBA pixels of a `size`×`size` icon.
pub fn rgba(size: u32) -> Vec<u8> {
    let s = size as f32;
    let center = s / 2.0;
    let radius = s / 2.0 - 1.0;
    let ring = (s / 16.0).max(1.5);
    let stroke = s / 9.0;
    // The "Y": two arms meeting in the middle, and a stem.
    let mid = (center, s * 0.52);
    let strokes = [
        ((s * 0.30, s * 0.26), mid),
        ((s * 0.70, s * 0.26), mid),
        (mid, (center, s * 0.76)),
    ];

    let mut pixels = Vec::with_capacity((size * size * 4) as usize);
    for y in 0..size {
        for x in 0..size {
            let p = (x as f32 + 0.5, y as f32 + 0.5);
            let dist = ((p.0 - center).powi(2) + (p.1 - center).powi(2)).sqrt();
            // Coverage values give soft (anti-aliased) edges.
            let disc = (radius - dist + 0.5).clamp(0.0, 1.0);
            let on_ring = (ring / 2.0 - (dist - (radius - ring / 2.0)).abs() + 0.5).clamp(0.0, 1.0);
            let on_y = strokes
                .iter()
                .map(|&(a, b)| (stroke / 2.0 - segment_distance(p, a, b) + 0.5).clamp(0.0, 1.0))
                .fold(0.0, f32::max);

            let mut color = [0x2b as f32, 0x24 as f32, 0x34 as f32];
            color = mix(color, [0xb9 as f32, 0x8c as f32, 0xff as f32], on_ring);
            color = mix(color, [0xe8 as f32, 0xde as f32, 0xfa as f32], on_y);
            pixels.extend(color.map(|c| c.round() as u8));
            pixels.push((disc * 255.0).round() as u8);
        }
    }
    pixels
}

fn mix(a: [f32; 3], b: [f32; 3], t: f32) -> [f32; 3] {
    [0, 1, 2].map(|i| a[i] + (b[i] - a[i]) * t)
}

fn segment_distance(p: (f32, f32), a: (f32, f32), b: (f32, f32)) -> f32 {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let t = (((p.0 - a.0) * dx + (p.1 - a.1) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
    ((p.0 - a.0 - t * dx).powi(2) + (p.1 - a.1 - t * dy).powi(2)).sqrt()
}
