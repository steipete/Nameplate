use crate::{config, platform};
use cairo::Context;
use gtk::prelude::*;
use nameplate_core::{Corner, Identity, Settings};
use std::cell::Cell;
use std::f64::consts::{FRAC_PI_2, PI};
use std::rc::Rc;
use std::time::{Duration, Instant};

pub struct OverlayManager {
    application: gtk::Application,
    config: config::LoadedConfig,
    decoration_windows: Vec<gtk::Window>,
    transient_windows: Vec<gtk::Window>,
    last_splash: Option<Instant>,
}

impl OverlayManager {
    pub fn new(application: &gtk::Application) -> Self {
        Self {
            application: application.clone(),
            config: config::load(),
            decoration_windows: Vec::new(),
            transient_windows: Vec::new(),
            last_splash: None,
        }
    }

    pub fn reload(&mut self) {
        self.config = config::load();
        self.rebuild();
    }

    pub fn rebuild(&mut self) {
        close_all(&mut self.decoration_windows);
        let monitors = monitors();
        for monitor in monitors {
            if self.config.settings.frame_enabled {
                self.decoration_windows.push(make_window(
                    &self.application,
                    &monitor,
                    DrawLayer::Frame,
                    &self.config.identity,
                    &self.config.settings,
                    platform::InputShape::Empty,
                ));
            }
            if self.config.settings.tag_enabled {
                self.decoration_windows.push(make_window(
                    &self.application,
                    &monitor,
                    DrawLayer::Tag,
                    &self.config.identity,
                    &self.config.settings,
                    platform::InputShape::Empty,
                ));
            }
            if self.config.settings.watermark_enabled {
                self.decoration_windows.push(make_window(
                    &self.application,
                    &monitor,
                    DrawLayer::Watermark,
                    &self.config.identity,
                    &self.config.settings,
                    platform::InputShape::Empty,
                ));
            }
        }
    }

    pub fn show_splash(&mut self, force: bool) {
        if !force {
            if !self.config.settings.splash_enabled {
                return;
            }
            if self
                .last_splash
                .is_some_and(|shown| shown.elapsed() < Duration::from_secs(8))
            {
                return;
            }
        }
        self.last_splash = Some(Instant::now());
        close_all(&mut self.transient_windows);
        self.transient_windows = monitors()
            .iter()
            .map(|monitor| {
                make_window(
                    &self.application,
                    monitor,
                    DrawLayer::Splash,
                    &self.config.identity,
                    &self.config.settings,
                    platform::InputShape::Empty,
                )
            })
            .collect();
        fade_in(&self.transient_windows);
        let windows = self.transient_windows.clone();
        let hold = self.config.settings.splash_duration.clamp(0.5, 10.0);
        gtk::glib::timeout_add_local_once(Duration::from_secs_f64(hold), move || {
            fade_out(windows);
        });
    }

    pub fn show_attention(
        &mut self,
        message: String,
        title: Option<String>,
        duration: Option<f64>,
        requested_color: Option<String>,
    ) {
        close_all(&mut self.transient_windows);
        let color = requested_color
            .as_deref()
            .and_then(nameplate_core::normalize_hex)
            .unwrap_or_else(|| self.config.identity.color.clone());
        let displays = monitors();
        let pulse = Rc::new(Cell::new(0.0));
        let mut windows = Vec::new();
        let mut pulse_areas = Vec::new();
        for monitor in &displays {
            let (window, area) = make_window_with_area(
                &self.application,
                monitor,
                DrawLayer::AttentionFrame {
                    color: color.clone(),
                    pulse: Rc::clone(&pulse),
                },
                &self.config.identity,
                &self.config.settings,
                platform::InputShape::Empty,
            );
            windows.push(window);
            pulse_areas.push(area);
        }

        if let Some(monitor) = displays.first() {
            let geometry = monitor.geometry();
            let card = attention_card_rect(geometry.width(), geometry.height());
            let (window, area) = make_window_with_area(
                &self.application,
                monitor,
                DrawLayer::AttentionCard {
                    color,
                    title: title.unwrap_or_else(|| "Agent needs attention".to_owned()),
                    message,
                },
                &self.config.identity,
                &self.config.settings,
                platform::InputShape::Rectangle(card),
            );
            windows.push(window);
            let dismiss_windows = windows.clone();
            let gesture = gtk::GestureClick::new();
            gesture.connect_released(move |_, _, _, _| {
                for window in &dismiss_windows {
                    window.close();
                }
            });
            area.add_controller(gesture);
        }

        let animation_windows = windows.clone();
        gtk::glib::timeout_add_local(Duration::from_millis(35), move || {
            if !animation_windows
                .iter()
                .any(gtk::prelude::WidgetExt::is_visible)
            {
                return gtk::glib::ControlFlow::Break;
            }
            pulse.set((pulse.get() + 0.05) % (2.0 * PI));
            for area in &pulse_areas {
                area.queue_draw();
            }
            gtk::glib::ControlFlow::Continue
        });
        // No duration = sticky until the card is clicked.
        if let Some(seconds) = duration {
            let timeout_windows = windows.clone();
            gtk::glib::timeout_add_local_once(
                Duration::from_secs_f64(seconds.clamp(2.0, 120.0)),
                move || fade_out(timeout_windows),
            );
        }
        self.transient_windows = windows;
    }
}

#[derive(Clone)]
enum DrawLayer {
    Frame,
    Tag,
    Watermark,
    Splash,
    AttentionFrame {
        color: String,
        pulse: Rc<Cell<f64>>,
    },
    AttentionCard {
        color: String,
        title: String,
        message: String,
    },
}

fn monitors() -> Vec<gtk::gdk::Monitor> {
    let Some(display) = gtk::gdk::Display::default() else {
        return Vec::new();
    };
    let model = display.monitors();
    (0..model.n_items())
        .filter_map(|index| model.item(index))
        .filter_map(|item| item.downcast::<gtk::gdk::Monitor>().ok())
        .collect()
}

fn make_window(
    application: &gtk::Application,
    monitor: &gtk::gdk::Monitor,
    layer: DrawLayer,
    identity: &Identity,
    settings: &Settings,
    input: platform::InputShape,
) -> gtk::Window {
    make_window_with_area(application, monitor, layer, identity, settings, input).0
}

fn make_window_with_area(
    application: &gtk::Application,
    monitor: &gtk::gdk::Monitor,
    layer: DrawLayer,
    identity: &Identity,
    settings: &Settings,
    input: platform::InputShape,
) -> (gtk::Window, gtk::DrawingArea) {
    let geometry = monitor.geometry();
    let window = gtk::Window::builder()
        .application(application)
        .decorated(false)
        .resizable(false)
        .focusable(false)
        .default_width(geometry.width())
        .default_height(geometry.height())
        .build();
    window.add_css_class("nameplate-overlay");
    window.set_can_focus(false);
    let area = gtk::DrawingArea::new();
    area.set_content_width(geometry.width());
    area.set_content_height(geometry.height());
    let identity = identity.clone();
    let settings = settings.clone();
    area.set_draw_func(move |_, context, width, height| {
        draw_layer(
            context,
            width as f64,
            height as f64,
            &layer,
            &identity,
            &settings,
        );
    });
    window.set_child(Some(&area));
    platform::prepare_window(&window, monitor, geometry, input);
    window.present();
    (window, area)
}

fn draw_layer(
    context: &Context,
    width: f64,
    height: f64,
    layer: &DrawLayer,
    identity: &Identity,
    settings: &Settings,
) {
    match layer {
        DrawLayer::Frame => draw_frame(context, width, height, identity, settings),
        DrawLayer::Tag => draw_tag(context, width, height, identity, settings),
        DrawLayer::Watermark => draw_watermark(context, width, height, identity, settings),
        DrawLayer::Splash => draw_splash(context, width, height, identity),
        DrawLayer::AttentionFrame { color, pulse } => {
            draw_attention_frame(context, width, height, color, pulse.get())
        }
        DrawLayer::AttentionCard {
            color,
            title,
            message,
        } => draw_attention_card(context, width, height, color, title, message, identity),
    }
}

fn draw_frame(
    context: &Context,
    width: f64,
    height: f64,
    identity: &Identity,
    settings: &Settings,
) {
    let thickness = settings.frame_thickness.clamp(1.0, 20.0);
    let inset = thickness / 2.0;
    let radius = settings.frame_corner_radius.max(0.0);
    uneven_rounded_rectangle(
        context,
        inset,
        inset,
        width - thickness,
        height - thickness,
        [
            if settings.frame_round_top_left {
                radius
            } else {
                0.0
            },
            if settings.frame_round_top_right {
                radius
            } else {
                0.0
            },
            if settings.frame_round_bottom_right {
                radius
            } else {
                0.0
            },
            if settings.frame_round_bottom_left {
                radius
            } else {
                0.0
            },
        ],
    );
    set_source_hex(
        context,
        &identity.color,
        settings.frame_opacity.clamp(0.0, 1.0),
    );
    context.set_line_width(thickness);
    let _ = context.stroke();
}

fn draw_tag(context: &Context, width: f64, height: f64, identity: &Identity, settings: &Settings) {
    let text = if settings.tag_shows_glyph && !identity.glyph.is_empty() {
        format!("{}  {}", identity.glyph, identity.name)
    } else {
        identity.name.clone()
    };
    context.select_font_face("Sans", cairo::FontSlant::Normal, cairo::FontWeight::Bold);
    context.set_font_size(13.0);
    let extents = context.text_extents(&text).ok();
    let text_width = extents
        .as_ref()
        .map_or(text.len() as f64 * 8.0, |e| e.x_advance());
    let pill_width = text_width + 22.0;
    let pill_height = 28.0;
    let pad = settings.frame_thickness.max(0.0) + 10.0;
    let (x, y) = corner_origin(
        settings.tag_corner,
        width,
        height,
        pill_width,
        pill_height,
        pad,
    );
    rounded_rectangle(context, x, y, pill_width, pill_height, pill_height / 2.0);
    set_source_hex(context, &identity.color, 1.0);
    let _ = context.fill();
    if nameplate_core::prefers_dark_text(&identity.color) {
        context.set_source_rgb(0.03, 0.03, 0.03);
    } else {
        context.set_source_rgb(1.0, 1.0, 1.0);
    }
    context.move_to(x + 11.0, y + 19.0);
    let _ = context.show_text(&text);
}

fn draw_watermark(
    context: &Context,
    width: f64,
    height: f64,
    identity: &Identity,
    settings: &Settings,
) {
    let text = identity.name.to_uppercase();
    let font_size = (width / (text.chars().count().max(4) as f64 * 0.72)).clamp(54.0, 112.0);
    context.select_font_face("Sans", cairo::FontSlant::Normal, cairo::FontWeight::Bold);
    context.set_font_size(font_size);
    let text_width = context
        .text_extents(&text)
        .map_or(width * 0.5, |e| e.x_advance());
    let (anchor_x, anchor_y) = match settings.watermark_corner {
        Corner::TopLeft => (width * 0.30, height * 0.30),
        Corner::TopRight => (width * 0.70, height * 0.30),
        Corner::BottomLeft => (width * 0.30, height * 0.72),
        Corner::BottomRight => (width * 0.70, height * 0.72),
    };
    let _ = context.save();
    context.translate(anchor_x, anchor_y);
    context.rotate(-0.16);
    context.move_to(-text_width / 2.0, font_size / 3.0);
    set_source_hex(
        context,
        &identity.color,
        settings.watermark_opacity.clamp(0.0, 0.3),
    );
    let _ = context.show_text(&text);
    let _ = context.restore();
}

fn draw_splash(context: &Context, width: f64, height: f64, identity: &Identity) {
    let card_width = width.clamp(360.0, 720.0);
    let card_height = if identity.glyph.is_empty() {
        190.0
    } else {
        270.0
    };
    let x = (width - card_width) / 2.0;
    let y = (height - card_height) / 2.0;
    rounded_rectangle(context, x, y, card_width, card_height, 32.0);
    context.set_source_rgba(0.0, 0.0, 0.0, 0.78);
    let _ = context.fill_preserve();
    set_source_hex(context, &identity.color, 1.0);
    context.set_line_width(4.0);
    let _ = context.stroke();
    let mut baseline = y + 78.0;
    if !identity.glyph.is_empty() {
        draw_centered_text(
            context,
            &identity.glyph,
            width / 2.0,
            baseline,
            72.0,
            false,
            (1.0, 1.0, 1.0, 1.0),
        );
        baseline += 88.0;
    }
    draw_centered_text(
        context,
        &identity.name,
        width / 2.0,
        baseline,
        58.0,
        true,
        (1.0, 1.0, 1.0, 1.0),
    );
    draw_centered_text(
        context,
        &identity.hostname,
        width / 2.0,
        y + card_height - 28.0,
        15.0,
        false,
        (1.0, 1.0, 1.0, 0.55),
    );
}

fn draw_attention_frame(context: &Context, width: f64, height: f64, color: &str, phase: f64) {
    let progress = (phase.sin() + 1.0) / 2.0;
    let thickness = 6.0 + progress * 8.0;
    rounded_rectangle(
        context,
        thickness / 2.0,
        thickness / 2.0,
        width - thickness,
        height - thickness,
        18.0,
    );
    set_source_hex(context, color, 0.45 + progress * 0.55);
    context.set_line_width(thickness);
    let _ = context.stroke();
}

fn attention_card_rect(width: i32, height: i32) -> cairo::RectangleInt {
    let card_width = width.clamp(320, 584);
    cairo::RectangleInt::new(
        (width - card_width) / 2,
        72.min(height / 8),
        card_width,
        190,
    )
}

fn draw_attention_card(
    context: &Context,
    width: f64,
    height: f64,
    color: &str,
    title: &str,
    message: &str,
    identity: &Identity,
) {
    let rect = attention_card_rect(width as i32, height as i32);
    let x = f64::from(rect.x());
    let y = f64::from(rect.y());
    let w = f64::from(rect.width());
    let h = f64::from(rect.height());
    rounded_rectangle(context, x + 8.0, y + 8.0, w - 16.0, h - 16.0, 24.0);
    context.set_source_rgba(0.0, 0.0, 0.0, 0.84);
    let _ = context.fill_preserve();
    set_source_hex(context, color, 1.0);
    context.set_line_width(3.0);
    let _ = context.stroke();
    draw_centered_text(
        context,
        title,
        width / 2.0,
        y + 55.0,
        26.0,
        true,
        (1.0, 1.0, 1.0, 1.0),
    );
    draw_centered_text(
        context,
        message,
        width / 2.0,
        y + 105.0,
        17.0,
        false,
        (1.0, 1.0, 1.0, 0.92),
    );
    draw_centered_text(
        context,
        &format!("{} · click to dismiss", identity.name),
        width / 2.0,
        y + 152.0,
        12.0,
        false,
        (1.0, 1.0, 1.0, 0.5),
    );
}

fn draw_centered_text(
    context: &Context,
    text: &str,
    center_x: f64,
    baseline: f64,
    size: f64,
    bold: bool,
    rgba: (f64, f64, f64, f64),
) {
    context.select_font_face(
        "Sans",
        cairo::FontSlant::Normal,
        if bold {
            cairo::FontWeight::Bold
        } else {
            cairo::FontWeight::Normal
        },
    );
    context.set_font_size(size);
    let width = context
        .text_extents(text)
        .map_or(text.len() as f64 * size * 0.5, |e| e.x_advance());
    context.set_source_rgba(rgba.0, rgba.1, rgba.2, rgba.3);
    context.move_to(center_x - width / 2.0, baseline);
    let _ = context.show_text(text);
}

fn corner_origin(
    corner: Corner,
    width: f64,
    height: f64,
    item_width: f64,
    item_height: f64,
    pad: f64,
) -> (f64, f64) {
    match corner {
        Corner::TopLeft => (pad, pad),
        Corner::TopRight => (width - item_width - pad, pad),
        Corner::BottomLeft => (pad, height - item_height - pad),
        Corner::BottomRight => (width - item_width - pad, height - item_height - pad),
    }
}

fn uneven_rounded_rectangle(context: &Context, x: f64, y: f64, w: f64, h: f64, radii: [f64; 4]) {
    let [tl, tr, br, bl] = radii.map(|radius| radius.clamp(0.0, w.min(h) / 2.0));
    context.new_sub_path();
    context.move_to(x + tl, y);
    context.line_to(x + w - tr, y);
    if tr > 0.0 {
        context.arc(x + w - tr, y + tr, tr, -FRAC_PI_2, 0.0);
    }
    context.line_to(x + w, y + h - br);
    if br > 0.0 {
        context.arc(x + w - br, y + h - br, br, 0.0, FRAC_PI_2);
    }
    context.line_to(x + bl, y + h);
    if bl > 0.0 {
        context.arc(x + bl, y + h - bl, bl, FRAC_PI_2, PI);
    }
    context.line_to(x, y + tl);
    if tl > 0.0 {
        context.arc(x + tl, y + tl, tl, PI, 3.0 * FRAC_PI_2);
    }
    context.close_path();
}

fn rounded_rectangle(context: &Context, x: f64, y: f64, w: f64, h: f64, radius: f64) {
    uneven_rounded_rectangle(context, x, y, w, h, [radius; 4]);
}

fn set_source_hex(context: &Context, hex: &str, alpha: f64) {
    let (red, green, blue) = nameplate_core::rgb(hex).unwrap_or((0.114, 0.62, 0.459));
    context.set_source_rgba(red, green, blue, alpha);
}

fn close_all(windows: &mut Vec<gtk::Window>) {
    for window in windows.drain(..) {
        window.close();
    }
}

fn fade_in(windows: &[gtk::Window]) {
    for window in windows {
        window.set_opacity(0.0);
    }
    let windows = windows.to_vec();
    gtk::glib::timeout_add_local(Duration::from_millis(16), move || {
        let opacity = windows
            .first()
            .map_or(1.0, gtk::prelude::WidgetExt::opacity)
            + 0.1;
        for window in &windows {
            window.set_opacity(opacity.min(1.0));
        }
        if opacity >= 1.0 {
            gtk::glib::ControlFlow::Break
        } else {
            gtk::glib::ControlFlow::Continue
        }
    });
}

fn fade_out(windows: Vec<gtk::Window>) {
    gtk::glib::timeout_add_local(Duration::from_millis(20), move || {
        let opacity = windows
            .first()
            .map_or(0.0, gtk::prelude::WidgetExt::opacity)
            - 0.05;
        if opacity <= 0.0 {
            for window in &windows {
                window.close();
            }
            gtk::glib::ControlFlow::Break
        } else {
            for window in &windows {
                window.set_opacity(opacity);
            }
            gtk::glib::ControlFlow::Continue
        }
    });
}
