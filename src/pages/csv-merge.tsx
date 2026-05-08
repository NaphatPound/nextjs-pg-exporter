'use client';

import React, { useEffect, useMemo, useState } from 'react';
import Papa from 'papaparse';
import * as XLSX from 'xlsx-js-style';
import Navigation from '../components/Navigation';

type Row = Record<string, any>;
type ColumnMapping = Record<string, string>; // file2Col -> file1Col

const STORAGE_KEY_MAP_ROWS = 'csv-merge-generic-mapping-rows';
const STORAGE_KEY_OUTPUT_MODE = 'csv-merge-output-mode';

type OutputMode = 'replace' | 'insert';

type MappingRow = {
    id: string;
    f1Col: string;
    f2Col: string;
    isKey: boolean;
};

function norm(v: any) {
    return String(v ?? '').trim();
}

function makeKey(r: Row, keyCols: string[]) {
    return keyCols.map(col => norm(r[col])).join('||');
}

function parseCsv(file: File): Promise<Row[]> {
    return new Promise((resolve, reject) => {
        Papa.parse<Row>(file, {
            header: true,
            skipEmptyLines: true,
            dynamicTyping: false,
            complete: (res) => {
                if (res.errors?.length) return reject(new Error(res.errors[0].message));
                resolve(res.data ?? []);
            },
        });
    });
}

function downloadArrayBuffer(buf: ArrayBuffer, filename: string) {
    const blob = new Blob([buf], {
        type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
}

function loadSavedMappingRows(): MappingRow[] {
    if (typeof window === 'undefined') return [];
    try {
        const saved = localStorage.getItem(STORAGE_KEY_MAP_ROWS);
        if (!saved) return [];
        const arr = JSON.parse(saved);
        return arr.map((r: any): MappingRow => {
            if (typeof r.isKey === 'boolean') {
                return { id: r.id, f1Col: r.f1Col ?? '', f2Col: r.f2Col ?? '', isKey: r.isKey };
            }
            return {
                id: r.id,
                f1Col: r.f1Col ?? '',
                f2Col: r.f2Col ?? '',
                isKey: r.mode === 'key',
            };
        });
    } catch {
        return [];
    }
}

function loadSavedOutputMode(): OutputMode {
    if (typeof window === 'undefined') return 'replace';
    try {
        const v = localStorage.getItem(STORAGE_KEY_OUTPUT_MODE);
        return v === 'insert' ? 'insert' : 'replace';
    } catch {
        return 'replace';
    }
}

function saveMappingRows(rows: MappingRow[]) {
    if (typeof window === 'undefined') return;
    try {
        localStorage.setItem(STORAGE_KEY_MAP_ROWS, JSON.stringify(rows));
    } catch { }
}

export default function CsvMergePage() {
    const [file1, setFile1] = useState<File | null>(null);
    const [file2, setFile2] = useState<File | null>(null);
    const [log, setLog] = useState<string>('');

    // Store data for live validation
    const [mappedIndex2, setMappedIndex2] = useState<Map<string, Row>>(new Map());
    const [activeReplaceCols, setActiveReplaceCols] = useState<string[]>([]);
    const [activeKeys, setActiveKeys] = useState<string[]>([]);

    const [cols1, setCols1] = useState<string[]>([]);
    const [cols2, setCols2] = useState<string[]>([]);
    const [mappingRows, setMappingRows] = useState<MappingRow[]>([]);
    const [outputMode, setOutputMode] = useState<OutputMode>('replace');

    // Load saved data on mount
    useEffect(() => {
        setMappingRows(loadSavedMappingRows());
        setOutputMode(loadSavedOutputMode());
    }, []);

    const updateOutputMode = (mode: OutputMode) => {
        setOutputMode(mode);
        if (typeof window !== 'undefined') {
            try { localStorage.setItem(STORAGE_KEY_OUTPUT_MODE, mode); } catch { }
        }
    };

    // Auto-detect columns when files are uploaded
    useEffect(() => {
        if (file1) {
            parseCsv(file1).then(rows => {
                if (rows.length > 0) {
                    const columns = Object.keys(rows[0]);
                    setCols1(columns);
                }
            }).catch(() => { });
        } else {
            setCols1([]);
        }
    }, [file1]);

    useEffect(() => {
        if (file2) {
            parseCsv(file2).then(rows => {
                if (rows.length > 0) {
                    const columns = Object.keys(rows[0]);
                    setCols2(columns);
                }
            }).catch(() => { });
        } else {
            setCols2([]);
        }
    }, [file2]);

    const addMappingRow = () => {
        const next: MappingRow[] = [...mappingRows, { id: crypto.randomUUID(), f1Col: '', f2Col: '', isKey: false }];
        setMappingRows(next);
        saveMappingRows(next);
    };

    const removeMappingRow = (id: string) => {
        const next = mappingRows.filter(r => r.id !== id);
        setMappingRows(next);
        saveMappingRows(next);
    };

    const updateMappingRow = (id: string, updates: Partial<MappingRow>) => {
        const next = mappingRows.map(r => r.id === id ? { ...r, ...updates } : r);
        setMappingRows(next);
        saveMappingRows(next);
    };

    const canRun = useMemo(() => {
        const keys = mappingRows.filter(r => r.isKey && r.f1Col && r.f2Col);
        return !!file1 && !!file2 && keys.length > 0;
    }, [file1, file2, mappingRows]);

    const reset = () => {
        setFile1(null);
        setFile2(null);
        setLog('');
        setCols1([]);
        setCols2([]);
        // Keep mapping rows preserved as per user request
        setMappedIndex2(new Map());
        setActiveReplaceCols([]);
        setActiveKeys([]);
    };

    const runMergeExport = async () => {
        const keys = mappingRows.filter(r => r.isKey && r.f1Col && r.f2Col);
        const nonKeys = mappingRows.filter(r => !r.isKey && r.f1Col && r.f2Col);
        // Replace mode: non-keys are replace mappings.
        // Insert mode: non-keys are insert mappings (f1Col = anchor, f2Col = source to insert).
        const updates = outputMode === 'replace' ? nonKeys : [];
        const inserts = outputMode === 'insert' ? nonKeys : [];

        if (!file1 || !file2 || keys.length === 0) return;

        setLog('Reading CSV files...');
        const rows1 = await parseCsv(file1);
        const rows2 = await parseCsv(file2);

        if (!rows1.length || !rows2.length) {
            throw new Error('One of the files is empty (no rows).');
        }

        const actualCols1 = Object.keys(rows1[0]);
        const actualCols2 = Object.keys(rows2[0]);

        const keyColsF1 = keys.map(k => k.f1Col);
        const replaceColsF1 = updates.map(u => u.f1Col);
        setActiveReplaceCols(replaceColsF1);
        setActiveKeys(keyColsF1);

        // ----- Insert mode: each insert row defines (anchor, start_col).
        // Insert all File 2 columns from start_col through the end of File 2, after the anchor.
        // Dedupe across insert rows: a given F2 column is inserted at most once (first row wins).
        const usedNames = new Set<string>(actualCols1);
        const seenF2Cols = new Set<string>();
        const insertOutputs: Array<{ newName: string; f2Col: string; anchor: string }> = [];
        for (const ins of inserts) {
            const startIdx = actualCols2.indexOf(ins.f2Col);
            if (startIdx === -1) continue;
            for (let i = startIdx; i < actualCols2.length; i++) {
                const f2Col = actualCols2[i];
                if (seenF2Cols.has(f2Col)) continue;
                seenF2Cols.add(f2Col);
                let newName = f2Col;
                let suffix = 1;
                while (usedNames.has(newName)) {
                    suffix += 1;
                    newName = `${f2Col}_${suffix}`;
                }
                usedNames.add(newName);
                insertOutputs.push({ newName, f2Col, anchor: ins.f1Col });
            }
        }

        const mappedRows2 = rows2.map(row => {
            const mappedRow: Row = {};
            for (const k of keys) {
                mappedRow[k.f1Col] = row[k.f2Col];
            }
            for (const u of updates) {
                mappedRow[u.f1Col] = row[u.f2Col];
            }
            for (const ins of insertOutputs) {
                mappedRow[ins.newName] = row[ins.f2Col];
            }
            return mappedRow;
        });

        const index2 = new Map<string, Row>();
        for (const r2 of mappedRows2) {
            index2.set(makeKey(r2, keyColsF1), r2);
        }
        setMappedIndex2(index2);

        setLog(`Merging (${outputMode})... keys: ${keyColsF1.join(', ')}${outputMode === 'replace' ? `, replaceCols: ${replaceColsF1.join(', ') || '(none)'}` : `, insertCols: ${insertOutputs.map(i => i.newName).join(', ') || '(none)'}`}`);

        const rows3: Row[] = [];
        for (const r1 of rows1) {
            const key = makeKey(r1, keyColsF1);
            const r2 = index2.get(key);
            const merged = { ...r1 };

            let isValid = !!r2;
            if (r2) {
                for (const colF1 of replaceColsF1) merged[colF1] = r2[colF1];
                for (const ins of insertOutputs) merged[ins.newName] = r2[ins.newName] ?? '';
            } else {
                for (const ins of insertOutputs) merged[ins.newName] = '';
            }
            merged['VALIDATION'] = isValid ? 'TRUE' : 'FALSE';
            rows3.push(merged);
        }

        // Build merged columns: F1 cols, with each insert col placed right after its anchor
        const mergedCols: string[] = [];
        for (const f1col of actualCols1) {
            mergedCols.push(f1col);
            for (const ins of insertOutputs) {
                if (ins.anchor === f1col) mergedCols.push(ins.newName);
            }
        }
        mergedCols.push('VALIDATION');
        const wb = XLSX.utils.book_new();

        // Helper to strip any trailing _ followed by digits (e.g., column_1 -> column)
        const stripHeaderSuffix = (name: string) => name.replace(/_\d+$/, '');

        // Convert Row[] to AOA for all sheets to ensure clean headers and style control
        const sheet1Aoa = [actualCols1.map(stripHeaderSuffix), ...rows1.map(r => actualCols1.map(c => r[c] ?? ''))];

        // In insert mode, append _COMP_KEY column to File2 (Original) so VALIDATION can
        // INDEX/MATCH against the original sheet. Composite key is built from F2 key columns
        // in the SAME order as keyColsF1 (so it matches the Merged-side composite key formula).
        const includeCompKeyInOriginal = outputMode === 'insert';
        const sheet2Header = includeCompKeyInOriginal ? [...actualCols2, '_COMP_KEY'] : actualCols2;
        const sheet2Aoa = [
            sheet2Header.map(h => h === '_COMP_KEY' ? h : stripHeaderSuffix(h)),
            ...rows2.map(r => {
                const baseRow = actualCols2.map(c => r[c] ?? '');
                if (!includeCompKeyInOriginal) return baseRow;
                const compKey = keys.map(k => norm(r[k.f2Col])).join('||');
                return [...baseRow, compKey];
            })
        ];

        XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(sheet1Aoa), 'File1');
        XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(sheet2Aoa), 'File2 (Original)');

        // Prepare File2 (Mapped) — lookup table for VLOOKUP formulas in Merged.VALIDATION column.
        // Contains only columns actually mapped from File 2 (keys + replace cols + insert cols),
        // so the sheet shows real data instead of empty F1-only columns.
        const seen = new Set<string>();
        const mappedSheetCols: string[] = [];
        for (const c of [...keyColsF1, ...replaceColsF1, ...insertOutputs.map(i => i.newName)]) {
            if (seen.has(c)) continue;
            seen.add(c);
            mappedSheetCols.push(c);
        }
        const mappedHeader = ['_COMP_KEY', ...mappedSheetCols];
        const ws2MappedAoa = [
            mappedHeader.map(h => h === '_COMP_KEY' ? h : stripHeaderSuffix(h)),
            ...mappedRows2.map(r => {
                const compKey = makeKey(r, keyColsF1).trim();
                return [compKey, ...mappedSheetCols.map(c => r[c] ?? '')];
            })
        ];
        XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(ws2MappedAoa), 'File2 (Mapped)');

        // Prepare Merged Sheet with formulas and styles
        const ws3Data: any[][] = [];
        ws3Data.push(mergedCols.map(stripHeaderSuffix));

        const getKeyFormula = (rowIdx: number) => {
            const parts = keyColsF1.map(k => {
                const kIdx = mergedCols.indexOf(k);
                // Apply TRIM to each part to match JS makeKey's norm() behavior
                return `TRIM(${XLSX.utils.encode_col(kIdx)}${rowIdx})`;
            });
            return parts.length === 1 ? parts[0] : parts.join('&"||"&');
        };

        const validatedCols = [...replaceColsF1, ...insertOutputs.map(i => i.newName)];
        const insertColToF2 = new Map(insertOutputs.map(i => [i.newName, i.f2Col]));
        // _COMP_KEY column letter in File2 (Original) — appended after all original cols in insert mode
        const origCompKeyLetter = XLSX.utils.encode_col(actualCols2.length);

        rows3.forEach((row, i) => {
            const excelRowIdx = i + 2;
            const rowData = mergedCols.map(col => {
                const val = row[col] ?? '';
                if (col === 'VALIDATION') {
                    const keyFrag = getKeyFormula(excelRowIdx);
                    const conditions: string[] = [];

                    if (outputMode === 'insert') {
                        // Insert mode: validate against File2 (Original) directly.
                        // 1) Key must exist in File2 (Original)._COMP_KEY → keys match
                        conditions.push(
                            `IFERROR(MATCH(${keyFrag}, 'File2 (Original)'!$${origCompKeyLetter}$2:$${origCompKeyLetter}$99999, 0)>0, FALSE)`
                        );
                        // 2) Each highlighted (insert) cell must equal the value at that row in File2 (Original)
                        for (const c of validatedCols) {
                            const targetColIdx = mergedCols.indexOf(c);
                            const targetColLetter = XLSX.utils.encode_col(targetColIdx);
                            const f2Col = insertColToF2.get(c);
                            if (!f2Col) continue;
                            const f2ColIdx = actualCols2.indexOf(f2Col);
                            if (f2ColIdx === -1) continue;
                            const f2ColLetter = XLSX.utils.encode_col(f2ColIdx);
                            conditions.push(
                                `TRIM(${targetColLetter}${excelRowIdx})=IFERROR(TRIM(INDEX('File2 (Original)'!$${f2ColLetter}$2:$${f2ColLetter}$99999, MATCH(${keyFrag}, 'File2 (Original)'!$${origCompKeyLetter}$2:$${origCompKeyLetter}$99999, 0))), "")`
                            );
                        }
                    } else {
                        // Replace mode: existing VLOOKUP into File2 (Mapped)
                        for (const c of validatedCols) {
                            const targetColIdx = mergedCols.indexOf(c);
                            const targetColLetter = XLSX.utils.encode_col(targetColIdx);
                            const vlookupIndex = mappedSheetCols.indexOf(c) + 2;
                            conditions.push(
                                `TRIM(${targetColLetter}${excelRowIdx})=IFERROR(TRIM(VLOOKUP(${keyFrag}, 'File2 (Mapped)'!$A$2:$ZZ$99999, ${vlookupIndex}, FALSE)), "")`
                            );
                        }
                    }

                    const formula = conditions.length > 0 ? `AND(${conditions.join(', ')})` : `TRIM(${keyFrag})<>""`;
                    return { t: 's', v: val, f: formula };
                }
                return val;
            });
            ws3Data.push(rowData);
        });

        // Tip for the user
        setLog(prev => prev + '\n📌 หมายเหตุ: สีพื้นหลังใน Excel เป็นแบบคงที่ จะไม่เปลี่ยนตามการแก้ไขในไฟล์ Excel (แต่ข้อความ TRUE/FALSE จะเปลี่ยนตามสูตร)');

        const ws3 = XLSX.utils.aoa_to_sheet(ws3Data);
        const GREEN = { patternType: 'solid', fgColor: { rgb: 'C6EFCE' }, bgColor: { rgb: 'C6EFCE' } };
        const RED = { patternType: 'solid', fgColor: { rgb: 'FFC7CE' }, bgColor: { rgb: 'FFC7CE' } };
        const ORANGE = { patternType: 'solid', fgColor: { rgb: 'FFD9A8' }, bgColor: { rgb: 'FFD9A8' } };

        // Header bold and centered
        mergedCols.forEach((_, c) => {
            const addr = XLSX.utils.encode_cell({ r: 0, c });
            if (ws3[addr]) ws3[addr].s = { font: { bold: true }, alignment: { horizontal: 'center' } };
        });

        rows3.forEach((r, i) => {
            const rIdx = i + 1; // row index in sheet (0-based)
            const r2 = index2.get(makeKey(rows1[i], keyColsF1));
            const isValid = r['VALIDATION'] === 'TRUE';

            // Color replacement columns: GREEN if changed from F1 to match F2, RED otherwise
            replaceColsF1.forEach(col => {
                const cIdx = mergedCols.indexOf(col);
                if (cIdx === -1) return;
                const addr = XLSX.utils.encode_cell({ r: rIdx, c: cIdx });
                if (ws3[addr]) {
                    const isMatchNoChange = !!r2 && norm(r[col]) === norm(r2[col]);
                    if (!isValid) ws3[addr].s = { fill: RED };
                    else ws3[addr].s = { fill: isMatchNoChange ? GREEN : RED };
                }
            });

            // Color insert columns: ORANGE always (distinguishes inserted columns)
            insertOutputs.forEach(ins => {
                const cIdx = mergedCols.indexOf(ins.newName);
                if (cIdx === -1) return;
                const addr = XLSX.utils.encode_cell({ r: rIdx, c: cIdx });
                if (ws3[addr]) ws3[addr].s = { fill: ORANGE };
            });
        });

        XLSX.utils.book_append_sheet(wb, ws3, 'Merged');

        const now = new Date();
        const yyyymmdd = now.getFullYear().toString() +
            (now.getMonth() + 1).toString().padStart(2, '0') +
            now.getDate().toString().padStart(2, '0');
        const filename = `รายงานผลการประเมิน_CreditScoring_รายย่อย_Agri_manual_${yyyymmdd}.xlsx`;

        downloadArrayBuffer(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }), filename);
        setLog('Done ✅');
    };


    return (
        <>
            <Navigation />
            <main>
                <h1>CSV Merge files to Excel 4 sheets</h1>
                <p>
                    เลือก <b>ไฟล์ 1</b> (ข้อมูลหลัก) และ <b>ไฟล์ 2</b> (ข้อมูลทับ/แก้ไข) จากนั้น map คอลัมน์ระหว่างไฟล์ และเลือกคอลัมน์คีย์
                    แล้ว export
                </p>

                <div className="grid">
                    <div className="card">
                        <div className="cardTitle">ไฟล์ 1 (หลัก)</div>
                        <input type="file" accept=".csv,text/csv" onChange={(e) => setFile1(e.target.files?.[0] ?? null)} />
                        <div className="small" style={{ marginTop: 8 }}>
                            {file1 ? (
                                <>
                                    <div>ชื่อไฟล์: {file1.name}</div>
                                    <div>ขนาด: {Math.round(file1.size / 1024)} KB</div>
                                    {cols1.length > 0 && <div>คอลัมน์: {cols1.length} คอลัมน์</div>}
                                </>
                            ) : (
                                <div>ยังไม่ได้เลือกไฟล์</div>
                            )}
                        </div>
                    </div>

                    <div className="card">
                        <div className="cardTitle">ไฟล์ 2 (แก้ไข/ทับค่า)</div>
                        <input type="file" accept=".csv,text/csv" onChange={(e) => setFile2(e.target.files?.[0] ?? null)} />
                        <div className="small" style={{ marginTop: 8 }}>
                            {file2 ? (
                                <>
                                    <div>ชื่อไฟล์: {file2.name}</div>
                                    <div>ขนาด: {Math.round(file2.size / 1024)} KB</div>
                                    {cols2.length > 0 && <div>คอลัมน์: {cols2.length} คอลัมน์</div>}
                                </>
                            ) : (
                                <div>ยังไม่ได้เลือกไฟล์</div>
                            )}
                        </div>
                    </div>
                </div>

                <div className="card" style={{ marginTop: 12 }}>
                    <div className="cardTitle">Output Mode</div>
                    <div style={{ display: 'flex', gap: 16, marginTop: 8 }}>
                        <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                            <input
                                type="radio"
                                name="outputMode"
                                value="replace"
                                checked={outputMode === 'replace'}
                                onChange={() => updateOutputMode('replace')}
                            />
                            <b>Replace</b>
                            <span className="small" style={{ marginLeft: 4 }}>— แทนค่าใน File 1 ด้วยค่าจาก File 2 (เลือก key + คอลัมน์ที่จะ replace)</span>
                        </label>
                        <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                            <input
                                type="radio"
                                name="outputMode"
                                value="insert"
                                checked={outputMode === 'insert'}
                                onChange={() => updateOutputMode('insert')}
                            />
                            <b>Insert After</b>
                            <span className="small" style={{ marginLeft: 4 }}>— ติ๊ก Is Key สำหรับแถวที่ใช้ match, แถวที่ไม่ติ๊ก: F2 = คอลัมน์เริ่มต้น (จะ insert ตั้งแต่คอลัมน์นั้นจนจบ File 2 หลัง F1 col ที่เลือก)</span>
                        </label>
                    </div>
                </div>

                <div className="row">
                    <button className="btn" disabled={!canRun} onClick={() => runMergeExport().catch((e) => setLog(`ERROR: ${e.message}`))}>
                        Merge + Export Excel
                    </button>
                    <button className="btn btnSecondary" onClick={reset}>
                        ล้างไฟล์
                    </button>
                    <div className="small">
                        {outputMode === 'replace' ? (
                            <>สีในชีต Merged: <b style={{ color: '#2e7d32' }}>เขียว</b> = file2==merged และ file2!=file1, <b style={{ color: '#c62828' }}>แดง</b> = อื่นๆ</>
                        ) : (
                            <>สีในชีต Merged: <b style={{ color: '#e65100' }}>ส้ม</b> = คอลัมน์ที่ insert จาก File 2</>
                        )}
                    </div>
                </div>

                {(cols1.length > 0 || cols2.length > 0) && (
                    <div className="card" style={{ marginTop: 12 }}>
                        <div className="cardTitle">
                            Mapping Configuration
                            <button className="btn btnSecondary" style={{ float: 'right', padding: '4px 10px', fontSize: '12px' }} onClick={addMappingRow}>+ Add Row</button>
                        </div>
                        <div style={{ marginTop: 12 }}>
                            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                                <thead>
                                    <tr style={{ textAlign: 'left', fontSize: '12px', borderBottom: '1px solid var(--border)' }}>
                                        <th style={{ padding: 8 }}>{outputMode === 'insert' ? 'File 1 (Target / Anchor)' : 'File 1 (Target)'}</th>
                                        <th style={{ padding: 8 }}>{outputMode === 'insert' ? 'File 2 (Source / Start col)' : 'File 2 (Source)'}</th>
                                        <th style={{ padding: 8, textAlign: 'center' }}>Is Key?</th>
                                        <th style={{ padding: 8, textAlign: 'center' }}>Action</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {mappingRows.map(row => (
                                        <tr key={row.id}>
                                            <td style={{ padding: 4 }}>
                                                <select
                                                    value={row.f1Col}
                                                    onChange={e => updateMappingRow(row.id, { f1Col: e.target.value })}
                                                    style={{ width: '100%' }}
                                                >
                                                    <option value="">-- Select F1 Col --</option>
                                                    {cols1.map(c => <option key={c} value={c}>{c}</option>)}
                                                </select>
                                            </td>
                                            <td style={{ padding: 4 }}>
                                                <select
                                                    value={row.f2Col}
                                                    onChange={e => updateMappingRow(row.id, { f2Col: e.target.value })}
                                                    style={{ width: '100%' }}
                                                >
                                                    <option value="">-- Select F2 Col --</option>
                                                    {cols2.map(c => <option key={c} value={c}>{c}</option>)}
                                                </select>
                                            </td>
                                            <td style={{ padding: 4, textAlign: 'center' }}>
                                                <input
                                                    type="checkbox"
                                                    checked={row.isKey}
                                                    onChange={e => updateMappingRow(row.id, { isKey: e.target.checked })}
                                                />
                                            </td>
                                            <td style={{ padding: 4, textAlign: 'center' }}>
                                                <button className="btn btnSecondary" style={{ padding: '4px 8px', color: '#ff6b6b' }} onClick={() => removeMappingRow(row.id)}>Remove</button>
                                            </td>
                                        </tr>
                                    ))}
                                    {mappingRows.length === 0 && (
                                        <tr>
                                            <td colSpan={4} style={{ padding: 20, textAlign: 'center', color: 'var(--muted)' }}>No mapping rows. Click "+ Add Row" to start.</td>
                                        </tr>
                                    )}
                                </tbody>
                            </table>
                        </div>
                    </div>
                )}


                {log && <pre className="pre">{log}</pre>}


                <div className="card" style={{ marginTop: 12 }}>
                    <div className="cardTitle">ข้อกำหนด CSV</div>
                    <div className="small">
                        <ul>
                            <li>ทั้ง 2 ไฟล์ต้องมีจำนวนแถวเท่ากัน</li>
                            <li>Map คอลัมน์ระหว่างไฟล์ 1 และไฟล์ 2 ให้ตรงกัน</li>
                            <li>เลือกคอลัมน์คีย์อย่างน้อย 1 คอลัมน์สำหรับ merge</li>
                            <li>ระบบจะจำการ map คอลัมน์ไว้ให้ครั้งถัดไป</li>
                        </ul>
                    </div>
                </div>
            </main>
        </>
    );
}
