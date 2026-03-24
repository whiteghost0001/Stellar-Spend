export default function Page() {
  return (
    <main className="min-h-screen bg-bg px-6 py-12 text-text sm:px-10">
      <div className="mx-auto flex w-full max-w-6xl flex-col gap-10">
        <section className="animate-scale-in rounded-[2rem] border border-line/70 bg-panel/80 p-8 shadow-[0_24px_80px_rgba(0,0,0,0.45)] backdrop-blur md:p-10">
          <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div className="max-w-2xl space-y-4">
              <p className="font-space-grotesk text-sm font-medium uppercase tracking-[0.35em] text-accent">
                Tailwind v4 token system
              </p>
              <div className="space-y-3">
                <h1 className="font-space-grotesk text-4xl font-semibold tracking-tight sm:text-5xl">
                  Stellar-Spend
                </h1>
                <p className="max-w-xl text-sm leading-7 text-muted sm:text-base">
                  Design tokens now live in Tailwind so components can use shared colors,
                  fonts, and animation utilities without inline styling workarounds.
                </p>
              </div>
            </div>

            <div className="flex items-center gap-3 rounded-full border border-line bg-bg/60 px-4 py-3 text-sm text-muted">
              <span className="inline-flex h-2.5 w-2.5 rounded-full bg-accent shadow-[0_0_18px_rgba(201,169,98,0.85)]" />
              Browser-ready motion preview
              <span className="ml-1 inline-flex gap-1">
                <span className="dot-bounce h-1.5 w-1.5 rounded-full bg-accent [animation-delay:0ms]" />
                <span className="dot-bounce h-1.5 w-1.5 rounded-full bg-accent [animation-delay:150ms]" />
                <span className="dot-bounce h-1.5 w-1.5 rounded-full bg-accent [animation-delay:300ms]" />
              </span>
            </div>
          </div>
        </section>

        <section className="grid gap-6 lg:grid-cols-[minmax(0,1.3fr)_minmax(20rem,0.7fr)]">
          <div className="racing-border-wrapper rounded-[1.75rem]">
            <div className="racing-border-content flex h-full flex-col justify-between rounded-[calc(1.75rem-2px)] border border-line/70 p-6 sm:p-8">
              <div className="space-y-4">
                <p className="font-space-grotesk text-xs font-medium uppercase tracking-[0.3em] text-accent">
                  Tokenized surfaces
                </p>
                <h2 className="font-space-grotesk text-2xl font-semibold text-text">
                  Shared primitives for the off-ramp dashboard
                </h2>
                <p className="max-w-2xl text-sm leading-7 text-muted">
                  `bg-bg`, `bg-panel`, `border-line`, `text-muted`, `text-accent`,
                  `font-space-grotesk`, and `font-ibm-plex-mono` now come directly from
                  Tailwind theme variables.
                </p>
              </div>

              <div className="mt-8 grid gap-3 sm:grid-cols-2">
                <div className="rounded-2xl border border-line/80 bg-bg/70 p-4">
                  <p className="text-xs uppercase tracking-[0.2em] text-muted">Accent</p>
                  <p className="mt-3 font-space-grotesk text-2xl text-accent">#C9A962</p>
                </div>
                <div className="rounded-2xl border border-line/80 bg-bg/70 p-4">
                  <p className="text-xs uppercase tracking-[0.2em] text-muted">Panel</p>
                  <p className="mt-3 font-space-grotesk text-2xl text-text">#111111</p>
                </div>
              </div>
            </div>
          </div>

          <div className="flex flex-col gap-6">
            <div className="rounded-[1.75rem] border border-line/70 bg-panel/90 p-6">
              <div className="flex items-center justify-between">
                <p className="font-space-grotesk text-lg font-medium text-text">
                  Animation utilities
                </p>
                <div className="animate-spin-slow rounded-full border border-accent/40 p-2">
                  <div className="h-4 w-4 rounded-full bg-accent" />
                </div>
              </div>
              <p className="mt-4 text-sm leading-7 text-muted">
                Custom animation classes are available as Tailwind utilities, while the
                racing border helpers stay defined globally for reusable component styling.
              </p>
            </div>

            <div className="rounded-[1.75rem] border border-line/70 bg-bg/70 p-6">
              <p className="font-space-grotesk text-lg font-medium text-text">Next step</p>
              <p className="mt-3 text-sm leading-7 text-muted">
                Build the dashboard UI on top of the shared token palette instead of
                hand-authored colors and inline layout rules.
              </p>
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
