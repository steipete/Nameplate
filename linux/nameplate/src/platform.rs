use cairo::Region;
use gtk::prelude::*;

pub fn prepare_window(
    window: &gtk::Window,
    _monitor: &gtk::gdk::Monitor,
    geometry: gtk::gdk::Rectangle,
) {
    #[cfg(all(target_os = "linux", feature = "layer-shell"))]
    if is_wayland(&_monitor.display()) {
        use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
        window.init_layer_shell();
        window.set_monitor(Some(_monitor));
        window.set_layer(Layer::Overlay);
        window.set_keyboard_mode(KeyboardMode::None);
        window.set_exclusive_zone(0);
        window.set_namespace(Some("nameplate"));
        for edge in [Edge::Left, Edge::Right, Edge::Top, Edge::Bottom] {
            window.set_anchor(edge, true);
        }
    }

    window.connect_realize(move |window| {
        let Some(surface) = window.surface() else {
            return;
        };
        let region = Region::create();
        surface.set_input_region(Some(&region));
        configure_x11(&surface, geometry);
    });
}

#[cfg(target_os = "linux")]
pub fn start_global_click_monitor(
    display: &gtk::gdk::Display,
    sender: std::sync::mpsc::Sender<crate::Event>,
) -> bool {
    use gdk4_x11::X11Display;
    use gdk4_x11::x11::{xinput2, xlib};
    use std::mem::{MaybeUninit, size_of_val};
    use std::os::raw::c_uchar;
    use std::ptr;

    if display.downcast_ref::<X11Display>().is_none() {
        return false;
    }

    std::thread::spawn(move || {
        let Ok(xlib) = xlib::Xlib::open() else {
            eprintln!("nameplate: cannot load Xlib for global click monitoring");
            return;
        };
        let Ok(xinput2) = xinput2::XInput2::open() else {
            eprintln!("nameplate: cannot load XInput2 for global click monitoring");
            return;
        };
        // SAFETY: this thread owns its Xlib display connection and closes it before exit.
        unsafe {
            let raw_display = (xlib.XOpenDisplay)(ptr::null());
            if raw_display.is_null() {
                eprintln!("nameplate: cannot open the X11 display for global click monitoring");
                return;
            }

            let mut major = 2;
            let mut minor = 0;
            if (xinput2.XIQueryVersion)(raw_display, &mut major, &mut minor) != 0 {
                eprintln!(
                    "nameplate: XInput2 is unavailable; attention clicks cannot be observed globally"
                );
                (xlib.XCloseDisplay)(raw_display);
                return;
            }

            let root = (xlib.XDefaultRootWindow)(raw_display);
            let mut mask = xinput2::XI_RawButtonPressMask;
            let mut event_mask = xinput2::XIEventMask {
                deviceid: xinput2::XIAllMasterDevices,
                mask: (&mut mask as *mut i32).cast::<c_uchar>(),
                mask_len: size_of_val(&mask) as i32,
            };
            (xinput2.XISelectEvents)(raw_display, root, &mut event_mask, 1);
            (xlib.XFlush)(raw_display);

            let mut event = MaybeUninit::<xlib::XEvent>::zeroed().assume_init();
            loop {
                (xlib.XNextEvent)(raw_display, &mut event);
                if event.get_type() != xlib::GenericEvent {
                    continue;
                }
                let mut cookie = event.generic_event_cookie;
                if (xlib.XGetEventData)(raw_display, &mut cookie) != xlib::True {
                    continue;
                }
                let is_button_press = cookie.evtype == xinput2::XI_RawButtonPress;
                (xlib.XFreeEventData)(raw_display, &mut cookie);
                if is_button_press
                    && sender
                        .send(crate::Event::GlobalClick(std::time::Instant::now()))
                        .is_err()
                {
                    break;
                }
            }
            (xlib.XCloseDisplay)(raw_display);
        }
    });
    true
}

#[cfg(not(target_os = "linux"))]
pub fn start_global_click_monitor(
    _display: &gtk::gdk::Display,
    _sender: std::sync::mpsc::Sender<crate::Event>,
) -> bool {
    false
}

#[cfg(all(target_os = "linux", feature = "layer-shell"))]
fn is_wayland(display: &gtk::gdk::Display) -> bool {
    display.type_().name().contains("Wayland")
}

#[cfg(target_os = "linux")]
fn configure_x11(surface: &gtk::gdk::Surface, geometry: gtk::gdk::Rectangle) {
    use gdk4_x11::{X11Display, X11Surface, x11::xlib};

    let Some(xsurface) = surface.downcast_ref::<X11Surface>() else {
        return;
    };
    let display = surface.display();
    let Some(xdisplay) = display.downcast_ref::<X11Display>() else {
        return;
    };
    let xid = xsurface.xid();
    let Ok(api) = xlib::Xlib::open() else {
        return;
    };
    // SAFETY: GDK owns this live X display; calls run on the GTK main thread.
    unsafe {
        let raw_display = xdisplay.xdisplay();
        // A reparenting window manager gives managed windows a separate frame whose
        // input shape remains interactive even when the GDK client region is empty.
        // Override-redirect keeps this overlay as the only X window in its stack,
        // so the empty region above truly passes the original click through.
        let mut attributes =
            std::mem::MaybeUninit::<xlib::XSetWindowAttributes>::zeroed().assume_init();
        attributes.override_redirect = xlib::True;
        (api.XChangeWindowAttributes)(raw_display, xid, xlib::CWOverrideRedirect, &mut attributes);
        let intern =
            |name: &[u8]| (api.XInternAtom)(raw_display, name.as_ptr().cast(), xlib::False);
        let net_wm_state = intern(b"_NET_WM_STATE\0");
        let states = [
            intern(b"_NET_WM_STATE_ABOVE\0"),
            intern(b"_NET_WM_STATE_SKIP_TASKBAR\0"),
            intern(b"_NET_WM_STATE_SKIP_PAGER\0"),
        ];
        (api.XChangeProperty)(
            raw_display,
            xid,
            net_wm_state,
            xlib::XA_ATOM,
            32,
            xlib::PropModeReplace,
            states.as_ptr().cast(),
            states.len() as i32,
        );
        let window_type = intern(b"_NET_WM_WINDOW_TYPE\0");
        let dock = intern(b"_NET_WM_WINDOW_TYPE_DOCK\0");
        (api.XChangeProperty)(
            raw_display,
            xid,
            window_type,
            xlib::XA_ATOM,
            32,
            xlib::PropModeReplace,
            (&dock as *const xlib::Atom).cast(),
            1,
        );
        (api.XMoveResizeWindow)(
            raw_display,
            xid,
            geometry.x(),
            geometry.y(),
            geometry.width() as u32,
            geometry.height() as u32,
        );
        (api.XRaiseWindow)(raw_display, xid);
        (api.XFlush)(raw_display);
    }
}

#[cfg(not(target_os = "linux"))]
fn configure_x11(_surface: &gtk::gdk::Surface, _geometry: gtk::gdk::Rectangle) {}
