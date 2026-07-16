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
    decoration_windows: Vec<DecorationWindow>,
    transient_windows: Vec<gtk::Window>,
    attention_active: Rc<Cell<bool>>,
    attention_generation: Rc<Cell<u64>>,
    attention_started: Option<Instant>,
    last_splash: Option<Instant>,
}

#[derive(Clone, Copy, Debug)]
struct SplashAnimation {
    elapsed: f64,
    hold: f64,
    reduce_motion: bool,
}

#[derive(Clone, Copy, Debug)]
struct SplashVisualState {
    frame_progress: f64,
    frame_opacity: f64,
    content_opacity: f64,
    content_scale: f64,
    glow_opacity: f64,
    glow_scale: f64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum DecorationLayer {
    Frame,
    Tag,
    Watermark,
}

impl DecorationLayer {
    const ORDERED: [Self; 3] = [Self::Frame, Self::Tag, Self::Watermark];

    fn draw_layer(self) -> DrawLayer {
        match self {
            Self::Frame => DrawLayer::Frame,
            Self::Tag => DrawLayer::Tag,
            Self::Watermark => DrawLayer::Watermark,
        }
    }

    fn is_enabled(self, settings: &Settings) -> bool {
        match self {
            Self::Frame => settings.frame_enabled,
            Self::Tag => settings.tag_enabled,
            Self::Watermark => settings.watermark_enabled,
        }
    }
}

struct DecorationWindow {
    layer: DecorationLayer,
    window: gtk::Window,
    animation_generation: Rc<Cell<u64>>,
}

impl OverlayManager {
    pub fn new(application: &gtk::Application) -> Self {
        Self {
            application: application.clone(),
            config: config::load(),
            decoration_windows: Vec::new(),
            transient_windows: Vec::new(),
            attention_active: Rc::new(Cell::new(false)),
            attention_generation: Rc::new(Cell::new(0)),
            attention_started: None,
            last_splash: None,
        }
    }

    pub fn reload(&mut self) {
        let next = config::load();
        if next == self.config {
            return;
        }
        let appearance_unchanged = self.config.identity == next.identity
            && decoration_appearance(&self.config.settings)
                == decoration_appearance(&next.settings);
        self.config = next;
        if appearance_unchanged {
            self.reconcile_enabled_layers(true);
        } else {
            self.replace_decorations(true);
        }
    }

    pub fn rebuild(&mut self) {
        self.replace_decorations(false);
    }

    fn replace_decorations(&mut self, animate: bool) {
        let previous = std::mem::take(&mut self.decoration_windows);
        for monitor in monitors() {
            for (layer, visible) in decoration_targets(&self.config.settings) {
                self.add_decoration(&monitor, layer, visible, animate);
            }
        }
        for decoration in previous {
            retire_decoration(decoration, animate);
        }
    }

    fn reconcile_enabled_layers(&mut self, animate: bool) {
        for decoration in &self.decoration_windows {
            let visible = decoration.layer.is_enabled(&self.config.settings);
            set_decoration_visibility(decoration, visible, animate);
        }
    }

    fn add_decoration(
        &mut self,
        monitor: &gtk::gdk::Monitor,
        layer: DecorationLayer,
        visible: bool,
        animate: bool,
    ) {
        let should_animate = visible && animate && animations_enabled();
        let window = make_window(
            &self.application,
            monitor,
            layer.draw_layer(),
            &self.config.identity,
            &self.config.settings,
            if visible && !should_animate { 1.0 } else { 0.0 },
        );
        let decoration = DecorationWindow {
            layer,
            window,
            animation_generation: Rc::new(Cell::new(0)),
        };
        if should_animate {
            animate_decoration(&decoration, 1.0, false);
        }
        self.decoration_windows.push(decoration);
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
        self.attention_generation
            .set(self.attention_generation.get().wrapping_add(1));
        self.attention_active.set(false);
        self.attention_started = None;
        close_all(&mut self.transient_windows);
        let hold = self.config.settings.splash_duration.clamp(0.5, 10.0);
        let reduce_motion =
            gtk::Settings::default().is_some_and(|settings| !settings.is_gtk_enable_animations());
        let animation = Rc::new(Cell::new(SplashAnimation {
            elapsed: 0.0,
            hold,
            reduce_motion,
        }));
        let mut windows = Vec::new();
        let mut areas = Vec::new();
        for monitor in monitors() {
            let (window, area) = make_window_with_area(
                &self.application,
                &monitor,
                DrawLayer::Splash {
                    animation: Rc::clone(&animation),
                },
                &self.config.identity,
                &self.config.settings,
                1.0,
            );
            windows.push(window);
            areas.push(area);
        }

        let animation_windows = windows.clone();
        let started = Instant::now();
        gtk::glib::timeout_add_local(Duration::from_millis(16), move || {
            let elapsed = started.elapsed().as_secs_f64();
            animation.set(SplashAnimation {
                elapsed,
                hold,
                reduce_motion,
            });
            for area in &areas {
                area.queue_draw();
            }
            if elapsed >= hold
                || !animation_windows
                    .iter()
                    .any(gtk::prelude::WidgetExt::is_visible)
            {
                gtk::glib::ControlFlow::Break
            } else {
                gtk::glib::ControlFlow::Continue
            }
        });

        let timeout_windows = windows.clone();
        gtk::glib::timeout_add_local_once(Duration::from_secs_f64(hold), move || {
            fade_out(timeout_windows);
        });
        self.transient_windows = windows;
    }

    pub fn show_attention(
        &mut self,
        message: String,
        title: Option<String>,
        duration: Option<f64>,
        requested_color: Option<String>,
    ) {
        let generation = self.attention_generation.get().wrapping_add(1);
        self.attention_generation.set(generation);
        self.attention_active.set(false);
        self.attention_started = Some(Instant::now());
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
                1.0,
            );
            windows.push(window);
            pulse_areas.push(area);
        }

        if let Some(monitor) = displays.first() {
            let (window, _) = make_window_with_area(
                &self.application,
                monitor,
                DrawLayer::AttentionCard {
                    color,
                    title: title.unwrap_or_else(|| "Agent needs attention".to_owned()),
                    message,
                },
                &self.config.identity,
                &self.config.settings,
                1.0,
            );
            windows.push(window);
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
            let attention_active = Rc::clone(&self.attention_active);
            let attention_generation = Rc::clone(&self.attention_generation);
            gtk::glib::timeout_add_local_once(
                Duration::from_secs_f64(seconds.clamp(2.0, 120.0)),
                move || {
                    if attention_generation.get() == generation {
                        attention_active.set(false);
                        fade_out(timeout_windows);
                    }
                },
            );
        }
        self.attention_active.set(!windows.is_empty());
        self.transient_windows = windows;
    }

    #[cfg(target_os = "linux")]
    pub fn dismiss_attention_from_click(&mut self, clicked_at: Instant) {
        if self.attention_active.get()
            && self
                .attention_started
                .is_some_and(|started| clicked_at >= started)
        {
            self.attention_active.set(false);
            self.attention_started = None;
            self.attention_generation
                .set(self.attention_generation.get().wrapping_add(1));
            close_all(&mut self.transient_windows);
        }
    }
}

#[derive(Clone)]
enum DrawLayer {
    Frame,
    Tag,
    Watermark,
    Splash {
        animation: Rc<Cell<SplashAnimation>>,
    },
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

#[derive(Clone, Copy, Debug, PartialEq)]
struct DecorationAppearance {
    frame_thickness: f64,
    frame_opacity: f64,
    frame_corner_radius: f64,
    frame_round_top_left: bool,
    frame_round_top_right: bool,
    frame_round_bottom_left: bool,
    frame_round_bottom_right: bool,
    tag_corner: Corner,
    tag_shows_glyph: bool,
    watermark_corner: Corner,
    watermark_opacity: f64,
}

fn decoration_appearance(settings: &Settings) -> DecorationAppearance {
    DecorationAppearance {
        frame_thickness: settings.frame_thickness,
        frame_opacity: settings.frame_opacity,
        frame_corner_radius: settings.frame_corner_radius,
        frame_round_top_left: settings.frame_round_top_left,
        frame_round_top_right: settings.frame_round_top_right,
        frame_round_bottom_left: settings.frame_round_bottom_left,
        frame_round_bottom_right: settings.frame_round_bottom_right,
        tag_corner: settings.tag_corner,
        tag_shows_glyph: settings.tag_shows_glyph,
        watermark_corner: settings.watermark_corner,
        watermark_opacity: settings.watermark_opacity,
    }
}

fn decoration_targets(settings: &Settings) -> [(DecorationLayer, bool); 3] {
    DecorationLayer::ORDERED.map(|layer| (layer, layer.is_enabled(settings)))
}

fn animations_enabled() -> bool {
    gtk::Settings::default().is_none_or(|settings| settings.is_gtk_enable_animations())
}

fn set_decoration_visibility(decoration: &DecorationWindow, visible: bool, animate: bool) {
    let target_opacity = if visible { 1.0 } else { 0.0 };
    decoration
        .animation_generation
        .set(decoration.animation_generation.get().wrapping_add(1));
    if (decoration.window.opacity() - target_opacity).abs() < f64::EPSILON {
        return;
    }
    if animate && animations_enabled() {
        animate_decoration(decoration, target_opacity, false);
    } else {
        decoration.window.set_opacity(target_opacity);
    }
}

fn retire_decoration(decoration: DecorationWindow, animate: bool) {
    if animate && animations_enabled() {
        animate_decoration(&decoration, 0.0, true);
    } else {
        decoration.window.close();
    }
}

fn animate_decoration(decoration: &DecorationWindow, target_opacity: f64, close: bool) {
    const DURATION: f64 = 0.2;

    let generation = decoration.animation_generation.get().wrapping_add(1);
    decoration.animation_generation.set(generation);
    let animation_generation = Rc::clone(&decoration.animation_generation);
    let window = decoration.window.clone();
    let initial_opacity = window.opacity();
    let started = Instant::now();
    gtk::glib::timeout_add_local(Duration::from_millis(16), move || {
        if animation_generation.get() != generation {
            return gtk::glib::ControlFlow::Break;
        }
        let animation_progress = (started.elapsed().as_secs_f64() / DURATION).clamp(0.0, 1.0);
        let opacity = lerp(
            initial_opacity,
            target_opacity,
            smoothstep(animation_progress),
        );
        window.set_opacity(opacity);
        if animation_progress >= 1.0 {
            if close {
                window.close();
            }
            gtk::glib::ControlFlow::Break
        } else {
            gtk::glib::ControlFlow::Continue
        }
    });
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
    initial_opacity: f64,
) -> gtk::Window {
    make_window_with_area(
        application,
        monitor,
        layer,
        identity,
        settings,
        initial_opacity,
    )
    .0
}

fn make_window_with_area(
    application: &gtk::Application,
    monitor: &gtk::gdk::Monitor,
    layer: DrawLayer,
    identity: &Identity,
    settings: &Settings,
    initial_opacity: f64,
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
    window.set_opacity(initial_opacity);
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
    platform::prepare_window(&window, monitor, geometry);
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
        DrawLayer::Splash { animation } => {
            draw_splash(context, width, height, identity, animation.get())
        }
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

fn splash_visual_state(animation: SplashAnimation) -> SplashVisualState {
    if animation.reduce_motion {
        let exit = ease_in(progress(
            animation.elapsed,
            (animation.hold - 0.2).max(0.0),
            0.2,
        ));
        let opacity = 1.0 - exit;
        return SplashVisualState {
            frame_progress: 1.0,
            frame_opacity: opacity,
            content_opacity: opacity,
            content_scale: 1.0,
            glow_opacity: opacity,
            glow_scale: 1.0,
        };
    }

    let frame_progress = smoothstep(progress(animation.elapsed, 0.0, 0.62));
    let glow_progress = ease_out(progress(animation.elapsed, 0.08, 0.55));
    let content_progress = progress(animation.elapsed, 0.2, 0.48);
    let content_spring = ease_out_back(content_progress);
    let exit = ease_in(progress(
        animation.elapsed,
        (animation.hold - 0.42).max(0.75),
        0.38,
    ));
    SplashVisualState {
        frame_progress,
        frame_opacity: 1.0 - exit,
        content_opacity: content_progress * (1.0 - exit),
        content_scale: lerp(0.88 + 0.12 * content_spring, 1.045, exit),
        glow_opacity: glow_progress * (1.0 - exit),
        glow_scale: lerp(0.78 + 0.25 * glow_progress, 1.08, exit),
    }
}

fn progress(elapsed: f64, delay: f64, duration: f64) -> f64 {
    ((elapsed - delay) / duration).clamp(0.0, 1.0)
}

fn smoothstep(value: f64) -> f64 {
    value * value * (3.0 - 2.0 * value)
}

fn ease_in(value: f64) -> f64 {
    value * value
}

fn ease_out(value: f64) -> f64 {
    1.0 - (1.0 - value).powi(3)
}

fn ease_out_back(value: f64) -> f64 {
    let offset = value - 1.0;
    let overshoot = 1.70158;
    1.0 + (overshoot + 1.0) * offset.powi(3) + overshoot * offset.powi(2)
}

fn lerp(from: f64, to: f64, progress: f64) -> f64 {
    from + (to - from) * progress
}

fn draw_splash(
    context: &Context,
    width: f64,
    height: f64,
    identity: &Identity,
    animation: SplashAnimation,
) {
    let visual = splash_visual_state(animation);
    draw_splash_frame(context, width, height, identity, visual);

    let card_width = width.clamp(360.0, 720.0);
    let card_height = if identity.glyph.is_empty() {
        190.0
    } else {
        270.0
    };
    let x = (width - card_width) / 2.0;
    let y = (height - card_height) / 2.0;
    let _ = context.save();
    context.translate(width / 2.0, height / 2.0);
    context.scale(visual.content_scale, visual.content_scale);
    context.translate(-width / 2.0, -height / 2.0);
    rounded_rectangle(
        context,
        x - 10.0,
        y - 10.0,
        card_width + 20.0,
        card_height + 20.0,
        38.0,
    );
    set_source_hex(context, &identity.color, 0.12 * visual.content_opacity);
    let _ = context.fill();
    rounded_rectangle(context, x, y, card_width, card_height, 32.0);
    context.set_source_rgba(0.0, 0.0, 0.0, 0.74 * visual.content_opacity);
    let _ = context.fill_preserve();
    set_source_hex(context, &identity.color, visual.content_opacity);
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
            (1.0, 1.0, 1.0, visual.content_opacity),
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
        (1.0, 1.0, 1.0, visual.content_opacity),
    );
    draw_centered_text(
        context,
        &identity.hostname,
        width / 2.0,
        y + card_height - 28.0,
        15.0,
        false,
        (1.0, 1.0, 1.0, 0.55 * visual.content_opacity),
    );
    let _ = context.restore();
}

fn draw_splash_frame(
    context: &Context,
    width: f64,
    height: f64,
    identity: &Identity,
    visual: SplashVisualState,
) {
    if visual.frame_progress > 0.0 && visual.frame_opacity > 0.0 {
        for (line_width, alpha) in [(28.0, 0.05), (18.0, 0.09), (7.0, 1.0)] {
            stroke_partial_rounded_frame(
                context,
                width,
                height,
                7.0,
                22.0,
                visual.frame_progress,
                line_width,
                identity,
                alpha * visual.frame_opacity,
            );
        }
    }

    if visual.glow_opacity > 0.0 {
        let _ = context.save();
        context.translate(width / 2.0, height / 2.0);
        context.scale(visual.glow_scale, visual.glow_scale);
        context.translate(-width / 2.0, -height / 2.0);
        rounded_rectangle(context, 7.0, 7.0, width - 14.0, height - 14.0, 22.0);
        set_source_hex(context, &identity.color, 0.16 * visual.glow_opacity);
        context.set_line_width(2.0);
        let _ = context.stroke();
        let _ = context.restore();
    }
}

#[allow(clippy::too_many_arguments)]
fn stroke_partial_rounded_frame(
    context: &Context,
    width: f64,
    height: f64,
    inset: f64,
    radius: f64,
    progress: f64,
    line_width: f64,
    identity: &Identity,
    alpha: f64,
) {
    let path_width = (width - 2.0 * inset).max(1.0);
    let path_height = (height - 2.0 * inset).max(1.0);
    let bounded_radius = radius.clamp(0.0, path_width.min(path_height) / 2.0);
    let perimeter =
        2.0 * (path_width + path_height - 4.0 * bounded_radius) + 2.0 * PI * bounded_radius;
    rounded_rectangle(
        context,
        inset,
        inset,
        path_width,
        path_height,
        bounded_radius,
    );
    context.set_dash(&[(perimeter * progress).max(0.01), perimeter], 0.0);
    context.set_line_cap(cairo::LineCap::Round);
    set_source_hex(context, &identity.color, alpha);
    context.set_line_width(line_width);
    let _ = context.stroke();
    context.set_dash(&[], 0.0);
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
        &format!("{} · click anywhere to dismiss", identity.name),
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decoration_appearance_ignores_non_decoration_settings() {
        let original = Settings::default();
        let toggled = Settings {
            name: Some("renamed".to_owned()),
            color: Some("#123456".to_owned()),
            glyph: Some("test".to_owned()),
            use_fleet_file: !original.use_fleet_file,
            frame_enabled: !original.frame_enabled,
            tag_enabled: !original.tag_enabled,
            watermark_enabled: !original.watermark_enabled,
            splash_enabled: !original.splash_enabled,
            splash_duration: original.splash_duration + 1.0,
            ..original.clone()
        };
        assert_eq!(
            decoration_appearance(&original),
            decoration_appearance(&toggled)
        );

        let restyled = Settings {
            frame_opacity: 0.25,
            ..original.clone()
        };
        assert_ne!(
            decoration_appearance(&original),
            decoration_appearance(&restyled)
        );
    }

    #[test]
    fn decoration_targets_keep_disabled_layers_in_canonical_order() {
        let settings = Settings {
            frame_enabled: true,
            tag_enabled: false,
            watermark_enabled: true,
            ..Settings::default()
        };
        assert_eq!(
            decoration_targets(&settings),
            [
                (DecorationLayer::Frame, true),
                (DecorationLayer::Tag, false),
                (DecorationLayer::Watermark, true),
            ]
        );
    }

    #[test]
    fn animated_splash_traces_then_exits() {
        let start = splash_visual_state(SplashAnimation {
            elapsed: 0.0,
            hold: 2.5,
            reduce_motion: false,
        });
        assert_eq!(start.frame_progress, 0.0);
        assert_eq!(start.content_opacity, 0.0);

        let presented = splash_visual_state(SplashAnimation {
            elapsed: 0.7,
            hold: 2.5,
            reduce_motion: false,
        });
        assert_eq!(presented.frame_progress, 1.0);
        assert_eq!(presented.content_opacity, 1.0);
        assert!(presented.glow_opacity > 0.99);

        let exited = splash_visual_state(SplashAnimation {
            elapsed: 2.5,
            hold: 2.5,
            reduce_motion: false,
        });
        assert!(exited.frame_opacity < 0.01);
        assert!(exited.content_opacity < 0.01);
        assert!(exited.glow_opacity < 0.01);
        assert!((exited.content_scale - 1.045).abs() < 0.001);
    }

    #[test]
    fn reduced_motion_splash_is_immediately_presented_and_only_fades() {
        let presented = splash_visual_state(SplashAnimation {
            elapsed: 0.0,
            hold: 2.5,
            reduce_motion: true,
        });
        assert_eq!(presented.frame_progress, 1.0);
        assert_eq!(presented.frame_opacity, 1.0);
        assert_eq!(presented.content_opacity, 1.0);
        assert_eq!(presented.content_scale, 1.0);
        assert_eq!(presented.glow_scale, 1.0);

        let exited = splash_visual_state(SplashAnimation {
            elapsed: 2.5,
            hold: 2.5,
            reduce_motion: true,
        });
        assert_eq!(exited.frame_opacity, 0.0);
        assert_eq!(exited.content_opacity, 0.0);
        assert_eq!(exited.content_scale, 1.0);
        assert_eq!(exited.glow_scale, 1.0);
    }
}
