// Minimal scenario/step engine with console + JSON reporting.
import { writeFileSync, mkdirSync } from 'node:fs'
import path from 'node:path'

const C = {
  green: (s: string) => `\x1b[32m${s}\x1b[0m`,
  red: (s: string) => `\x1b[31m${s}\x1b[0m`,
  yellow: (s: string) => `\x1b[33m${s}\x1b[0m`,
  dim: (s: string) => `\x1b[2m${s}\x1b[0m`,
  bold: (s: string) => `\x1b[1m${s}\x1b[0m`,
}

export interface StepResult {
  name: string
  status: 'pass' | 'fail'
  ms: number
  error?: string
}

export interface ScenarioResult {
  name: string
  status: 'pass' | 'fail' | 'skip'
  ms: number
  steps: StepResult[]
  error?: string
}

export interface T {
  /** Run a named step; failure aborts the rest of the scenario. */
  step<R>(name: string, fn: () => Promise<R>): Promise<R>
  log(msg: string): void
}

export interface Scenario {
  id: string
  title: string
  run(t: T): Promise<void>
}

export function scenario(id: string, title: string, run: (t: T) => Promise<void>): Scenario {
  return { id, title, run }
}

export async function runScenarios(
  scenarios: Scenario[],
  opts: { only?: string; bail?: boolean; verbose?: boolean },
): Promise<ScenarioResult[]> {
  const selected = opts.only
    ? scenarios.filter((s) => s.id.includes(opts.only!) || s.title.toLowerCase().includes(opts.only!.toLowerCase()))
    : scenarios
  if (selected.length === 0) {
    console.error(`No scenarios match --only=${opts.only}`)
    process.exit(2)
  }

  const results: ScenarioResult[] = []
  let aborted = false

  for (const sc of scenarios) {
    if (!selected.includes(sc)) {
      results.push({ name: sc.title, status: 'skip', ms: 0, steps: [] })
      continue
    }
    if (aborted) {
      results.push({ name: sc.title, status: 'skip', ms: 0, steps: [] })
      console.log(`${C.yellow('↷ SKIP')} ${sc.title} ${C.dim('(bail)')}`)
      continue
    }

    console.log(`\n${C.bold(`▶ ${sc.title}`)} ${C.dim(`[${sc.id}]`)}`)
    const steps: StepResult[] = []
    const started = Date.now()
    let failed: string | undefined

    const t: T = {
      async step(name, fn) {
        const t0 = Date.now()
        try {
          const r = await fn()
          steps.push({ name, status: 'pass', ms: Date.now() - t0 })
          console.log(`  ${C.green('✔')} ${name} ${C.dim(`${Date.now() - t0}ms`)}`)
          return r
        } catch (e: any) {
          const msg = e?.message ?? String(e)
          steps.push({ name, status: 'fail', ms: Date.now() - t0, error: msg })
          console.log(`  ${C.red('✘')} ${name}\n    ${C.red(msg.split('\n').join('\n    '))}`)
          throw e
        }
      },
      log(msg) {
        if (opts.verbose) console.log(`  ${C.dim('·')} ${C.dim(msg)}`)
      },
    }

    try {
      await sc.run(t)
    } catch (e: any) {
      failed = e?.message ?? String(e)
    }

    results.push({
      name: sc.title,
      status: failed ? 'fail' : 'pass',
      ms: Date.now() - started,
      steps,
      error: failed,
    })
    if (failed && opts.bail) aborted = true
  }

  return results
}

export function printSummary(results: ScenarioResult[]): boolean {
  const pass = results.filter((r) => r.status === 'pass').length
  const fail = results.filter((r) => r.status === 'fail').length
  const skip = results.filter((r) => r.status === 'skip').length
  const totalSteps = results.reduce((n, r) => n + r.steps.length, 0)

  console.log(`\n${C.bold('═══ Summary ═══')}`)
  for (const r of results) {
    const icon = r.status === 'pass' ? C.green('✔') : r.status === 'fail' ? C.red('✘') : C.yellow('↷')
    console.log(`${icon} ${r.name} ${C.dim(`(${r.steps.length} steps, ${r.ms}ms)`)}`)
  }
  console.log(
    `\n${C.bold(`${pass} passed`)}, ${fail ? C.red(`${fail} failed`) : '0 failed'}, ${skip} skipped — ${totalSteps} steps total\n`,
  )
  return fail === 0
}

export function writeReport(results: ScenarioResult[], runId: string): string {
  const dir = path.join(process.cwd(), 'reports')
  mkdirSync(dir, { recursive: true })
  const file = path.join(dir, `e2e-report-${runId}.json`)
  writeFileSync(
    file,
    JSON.stringify(
      {
        runId,
        finishedAt: new Date().toISOString(),
        summary: {
          passed: results.filter((r) => r.status === 'pass').length,
          failed: results.filter((r) => r.status === 'fail').length,
          skipped: results.filter((r) => r.status === 'skip').length,
        },
        scenarios: results,
      },
      null,
      2,
    ),
  )
  return file
}
