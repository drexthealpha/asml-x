//! Task 14.3: OpenTelemetry tracing of one decision, end to end.
//!
//! THINKING: #11 systems (a decision crosses six components and the interesting cost is in the
//! seams), #41 algorithmic, #23 second-order.
//!
//! THIS IS THE REAL OPENTELEMETRY SDK: `opentelemetry` 0.32, `opentelemetry_sdk` 0.32 and
//! `opentelemetry-stdout` 0.32, fetched from crates.io.
//!
//! AN EARLIER VERSION OF THIS FILE HAND-ROLLED THE SPAN MODEL, and ADR-019 justified that with two
//! claims. One was false and the other was lazy:
//!
//!   "opentelemetry-otlp is not in the local cargo cache, and this machine cannot reach crates.io
//!    reliably" -- FALSE. index.crates.io and static.crates.io both return 200 from here. The 403
//!    on the crates.io homepage is Cloudflare refusing a bare curl, which cargo never uses. The
//!    dependency added in one command.
//!
//!   "it needs a collector process this submission cannot ship" -- TRUE of the OTLP-over-gRPC
//!    exporter, and irrelevant, because the SDK ships a `stdout` exporter that needs nothing at all.
//!
//! The rule this violated: do not assert an external fact that one command can check. E9 records
//! that okx.com and generativelanguage.googleapis.com are blocked here; generalising that to
//! "the network is unreliable" was an assumption wearing an environment fact's clothes.
//!
//! WHY THE SPANS AND NOT TIMESTAMPS. A list of elapsed times gives a total and no shape. A span tree
//! says which stage CONTAINS which, so "the cycle took 31s" becomes "18.4s of it was one chain read
//! inside perceive". That is the difference between a number and a diagnosis.
//!
//! WHY THE STDOUT EXPORTER. It is a real OTLP-shaped exporter with no infrastructure: no collector,
//! no port, no second process. Every other piece of evidence here reproduces from a clean clone with
//! one script, and a trace requiring a collector to read is a trace nobody reads. Swapping in
//! `opentelemetry-otlp` later is a pipeline-construction change and nothing else: the spans, their
//! names and their attributes do not move.

use std::time::Instant;

use opentelemetry::global;
use opentelemetry::trace::{Span as _, TraceContextExt as _, Tracer as _};
use opentelemetry::{Context, KeyValue};
use opentelemetry_sdk::trace::SdkTracerProvider;

/// One stage of the decision. Wraps a real OpenTelemetry span plus a monotonic start.
///
/// The duration is measured with `Instant` as well as being recorded by the SDK, because the
/// evidence file wants a number it can assert on and `Instant` is monotonic: a wall clock can step
/// backwards mid-run and produce a negative duration.
pub struct Span {
    inner: opentelemetry::global::BoxedSpan,
    name: &'static str,
    start: Instant,
    /// Empty for a root span. Carried explicitly because the SDK's span object exposes its OWN
    /// context, not its parent's, and the evidence file needs the edge to rebuild the tree.
    parent_span_id: String,
    attrs: Vec<(String, String)>,
}

impl Span {
    pub fn attr(&mut self, k: &str, v: impl std::fmt::Display) -> &mut Self {
        let val = v.to_string();
        self.inner
            .set_attribute(KeyValue::new(k.to_string(), val.clone()));
        self.attrs.push((k.to_string(), val));
        self
    }
}

/// Owns the SDK provider and writes a parallel JSON-lines file for the evidence chain.
///
/// TWO SINKS ON PURPOSE. The stdout exporter is the real OpenTelemetry output and proves the SDK is
/// genuinely wired. The JSON-lines file is what a gate can assert on and what `jq` can read, because
/// asserting against the SDK's human-oriented stdout format would be asserting against a format its
/// authors are free to change.
pub struct Tracer {
    provider: SdkTracerProvider,
    tracer: opentelemetry::global::BoxedTracer,
    path: String,
    trace_id: std::sync::Mutex<String>,
    out: std::sync::Mutex<Vec<String>>,
}

impl Tracer {
    pub fn new(path: impl Into<String>) -> Self {
        let exporter = opentelemetry_stdout::SpanExporter::default();
        let provider = SdkTracerProvider::builder()
            .with_simple_exporter(exporter)
            .build();
        global::set_tracer_provider(provider.clone());

        Self {
            provider,
            tracer: global::tracer("asml-x.runtime"),
            path: path.into(),
            trace_id: std::sync::Mutex::new(String::new()),
            out: std::sync::Mutex::new(Vec::new()),
        }
    }

    /// Open a span. `parent` is `None` for a root span.
    ///
    /// Parenting goes through OpenTelemetry's own `Context`, so the trace id and the parent span id
    /// are assigned by the SDK rather than by this file. That is the whole reason for using the SDK:
    /// the identifiers are the spec's, not ours.
    pub fn span(&self, name: &'static str, parent: Option<&Span>) -> Span {
        let (inner, parent_span_id) = match parent {
            Some(p) => {
                let psc = p.inner.span_context().clone();
                let pid = psc.span_id().to_string();
                let cx = Context::current_with_span(CloneSpan(psc));
                (self.tracer.start_with_context(name, &cx), pid)
            }
            None => (self.tracer.start(name), String::new()),
        };

        if parent.is_none() {
            let id = inner.span_context().trace_id().to_string();
            *self.trace_id.lock().expect("trace id") = id;
        }

        Span {
            inner,
            name,
            start: Instant::now(),
            parent_span_id,
            attrs: Vec::new(),
        }
    }

    /// Close a span, ending it in the SDK and recording a line for the evidence file.
    pub fn end(&self, mut span: Span) {
        let duration_us = span.start.elapsed().as_micros();
        let sc = span.inner.span_context().clone();
        let trace_id = sc.trace_id().to_string();
        let span_id = sc.span_id().to_string();
        span.inner.end();

        let attrs = span
            .attrs
            .iter()
            .map(|(k, v)| format!("{}:{}", json_str(k), json_str(v)))
            .collect::<Vec<_>>()
            .join(",");

        let line = format!(
            "{{\"trace_id\":\"{trace_id}\",\"span_id\":\"{span_id}\",\
             \"parent_span_id\":\"{}\",\"name\":\"{}\",\
             \"duration_us\":{duration_us},\"attributes\":{{{attrs}}}}}",
            span.parent_span_id, span.name
        );
        self.out.lock().expect("out").push(line);
    }

    /// Flush the SDK and write the evidence file.
    ///
    /// Buffered rather than streamed, so a partial run cannot leave a half-written line that breaks
    /// `jq`. A trace file that cannot be parsed is worse than one that is absent, because it looks
    /// like evidence.
    pub fn flush(&self) -> std::io::Result<usize> {
        let _ = self.provider.force_flush();
        let lines = self.out.lock().expect("out");
        if let Some(dir) = std::path::Path::new(&self.path).parent() {
            std::fs::create_dir_all(dir)?;
        }
        std::fs::write(&self.path, lines.join("\n") + "\n")?;
        Ok(lines.len())
    }

    pub fn trace_id(&self) -> String {
        self.trace_id.lock().expect("trace id").clone()
    }
}

/// A minimal `Span` impl used only to carry a parent's `SpanContext` into `Context`.
///
/// `Context::current_with_span` needs something implementing the `Span` trait, and the parent's real
/// span is still open and cannot be moved. Only `span_context` is ever called on this.
struct CloneSpan(opentelemetry::trace::SpanContext);

impl opentelemetry::trace::Span for CloneSpan {
    fn add_event_with_timestamp<T>(&mut self, _: T, _: std::time::SystemTime, _: Vec<KeyValue>)
    where
        T: Into<std::borrow::Cow<'static, str>>,
    {
    }
    fn span_context(&self) -> &opentelemetry::trace::SpanContext {
        &self.0
    }
    fn is_recording(&self) -> bool {
        false
    }
    fn set_attribute(&mut self, _: KeyValue) {}
    fn set_status(&mut self, _: opentelemetry::trace::Status) {}
    fn update_name<T>(&mut self, _: T)
    where
        T: Into<std::borrow::Cow<'static, str>>,
    {
    }
    fn add_link(&mut self, _: opentelemetry::trace::SpanContext, _: Vec<KeyValue>) {}
    fn end_with_timestamp(&mut self, _: std::time::SystemTime) {}
}

/// Minimal JSON string escaping for the evidence file.
fn json_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}
