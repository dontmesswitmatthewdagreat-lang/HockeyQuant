import { useState } from 'react';
import './Advanced.css';

/**
 * Line chemistry (web port of the iOS LineChemistryView).
 *
 * Chemistry is the unit's xGF% minus what its members manage in their *other*
 * minutes, with each member's baseline excluding this unit's own time so the
 * unit can't predict itself. It is clamped to +/-15 and labelled "vs. their
 * other minutes" because those baselines are still contaminated by whatever
 * else the members play together.
 *
 * MoneyPuck's lines.csv has a 600-second floor, which covers D-pairs well but
 * leaves forward trios at ~83% — so with/without is deliberately not shown for
 * forwards, and units under 90% coverage are dropped upstream rather than
 * footnoted.
 */

function fmt(value, digits = 1, signed = false) {
  if (value === null || value === undefined) return '—';
  const s = value.toFixed(digits);
  return signed && value > 0 ? `+${s}` : s;
}

function chemistryTone(value) {
  if (value === null || value === undefined) return '';
  if (value >= 3) return 'adv-pos-text';
  if (value <= -3) return 'adv-neg-text';
  return '';
}

function UnitRow({ unit }) {
  const names = (unit.players || []).map((p) => p.name).join(' · ');
  return (
    <tr>
      <td className="adv-unit-names">
        <span>{names}</span>
        <span className="adv-unit-sub">
          {unit.minutes} min · {unit.games_played} GP
        </span>
      </td>
      <td>{fmt(unit.xgf_pct)}%</td>
      <td>{fmt(unit.gf_pct)}%</td>
      <td>{fmt(unit.hdcf_pct)}%</td>
      <td className={chemistryTone(unit.chemistry)}>{fmt(unit.chemistry, 1, true)}</td>
    </tr>
  );
}

function UnitTable({ units }) {
  return (
    <table className="adv-unit-table">
      <thead>
        <tr>
          <th>Unit</th>
          <th>xGF%</th>
          <th>GF%</th>
          <th>HDCF%</th>
          <th>Chem</th>
        </tr>
      </thead>
      <tbody>
        {units.map((u) => (
          <UnitRow key={(u.players || []).map((p) => p.player_id).join('-')} unit={u} />
        ))}
      </tbody>
    </table>
  );
}

function LineChemistry({ data }) {
  const [tab, setTab] = useState('lines');
  if (!data || !data.available) return null;

  const lines = data.lines || [];
  const pairs = data.pairs || [];
  if (lines.length === 0 && pairs.length === 0) return null;

  const units = tab === 'lines' ? lines : pairs;

  return (
    <div className="adv-card">
      <div className="adv-card-head">
        <h4>Line chemistry</h4>
      </div>

      <div className="adv-tabs">
        <button
          type="button"
          className={tab === 'lines' ? 'adv-tab active' : 'adv-tab'}
          onClick={() => setTab('lines')}
          disabled={lines.length === 0}
        >
          Forward lines ({lines.length})
        </button>
        <button
          type="button"
          className={tab === 'pairs' ? 'adv-tab active' : 'adv-tab'}
          onClick={() => setTab('pairs')}
          disabled={pairs.length === 0}
        >
          D pairs ({pairs.length})
        </button>
      </div>

      {units.length > 0 ? (
        <UnitTable units={units} />
      ) : (
        <p className="adv-note">No qualifying units yet this season.</p>
      )}

      <p className="adv-footnote">
        Chem is the unit&rsquo;s xGF% against what those same players manage in
        their other minutes — so it reads as lift from playing together, not
        raw quality. Clamped to ±15.
      </p>
    </div>
  );
}

export default LineChemistry;
