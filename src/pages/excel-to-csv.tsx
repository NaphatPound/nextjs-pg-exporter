'use client';

import React, { useState } from 'react';
import * as XLSX from 'xlsx-js-style';
import Papa from 'papaparse';
import Navigation from '../components/Navigation';

type Row = Record<string, any>;

function downloadCSV(data: string, filename: string) {
    // Add UTF-8 BOM for Excel compatibility with Thai characters
    const BOM = '\uFEFF';
    const csvWithBOM = BOM + data;
    const blob = new Blob([csvWithBOM], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
}

export default function ExcelToCsvPage() {
    const [file, setFile] = useState<File | null>(null);
    const [data, setData] = useState<Row[]>([]);
    const [columns, setColumns] = useState<string[]>([]);
    const [log, setLog] = useState<string>('');
    const [originalFilename, setOriginalFilename] = useState<string>('');

    const handleFileUpload = async (uploadedFile: File) => {
        setFile(uploadedFile);
        setLog('Reading Excel file...');
        setOriginalFilename(uploadedFile.name.replace(/\\.xlsx?$/i, ''));

        try {
            const arrayBuffer = await uploadedFile.arrayBuffer();
            const workbook = XLSX.read(arrayBuffer, { type: 'array' });

            // Check if "Merged" sheet exists
            if (!workbook.SheetNames.includes('Merged')) {
                throw new Error('Sheet "Merged" not found in this Excel file. Please upload a file exported from CSV Merge.');
            }

            const sheet = workbook.Sheets['Merged'];
            const jsonData = XLSX.utils.sheet_to_json<Row>(sheet, { defval: '' });

            if (!jsonData.length) {
                throw new Error('The "Merged" sheet is empty.');
            }

            // Get all columns and strip _1, _2, etc. suffixes (e.g. column_1 → column).
            // This matches the header-normalization done by the CSV Merge exporter.
            const allColumns = Object.keys(jsonData[0]);
            const cleanedColumns = allColumns.map(col => col.replace(/_\d+$/, ''));

            // Remove VALIDATION column from the cleaned headers
            const filteredColumns = cleanedColumns.filter(col => col !== 'VALIDATION');

            // Rebuild rows using cleaned column names, sourcing values from the original keys
            const filteredData = jsonData.map(row => {
                const newRow: Row = {};
                allColumns.forEach((originalCol, index) => {
                    const cleanCol = cleanedColumns[index];
                    if (cleanCol !== 'VALIDATION') {
                        newRow[cleanCol] = row[originalCol];
                    }
                });
                return newRow;
            });

            setColumns(filteredColumns);
            setData(filteredData);
            setLog(`✅ Successfully loaded ${filteredData.length} rows from "Merged" sheet. VALIDATION column removed.`);
        } catch (error: any) {
            setLog(`❌ Error: ${error.message}`);
            setData([]);
            setColumns([]);
        }
    };

    const handleDownloadCSV = () => {
        if (!data.length) {
            setLog('❌ No data to export.');
            return;
        }

        const csv = Papa.unparse(data, {
            columns: columns,
            header: true,
        });

        // Generate filename with current date
        const now = new Date();
        const yyyymmdd = now.getFullYear().toString() +
            (now.getMonth() + 1).toString().padStart(2, '0') +
            now.getDate().toString().padStart(2, '0');
        const filename = `รายงานผลการประเมิน_CreditScoring_รายย่อย_Agri_manual_${yyyymmdd}.csv`;

        downloadCSV(csv, filename);
        setLog(`✅ Downloaded: ${filename}`);
    };

    const reset = () => {
        setFile(null);
        setData([]);
        setColumns([]);
        setLog('');
        setOriginalFilename('');
    };

    return (
        <>
            <Navigation />
            <main>
                <h1>Excel to CSV Converter</h1>
                <p>
                    Upload ไฟล์ Excel ที่ export มาจาก <b>CSV Merge Tool</b> เพื่ออ่านข้อมูลจาก Sheet <b>"Merged"</b>
                    และ export เป็น CSV โดยตัดคอลัมน์ <b>VALIDATION</b> ออกอัตโนมัติ
                </p>

                <div className="card">
                    <div className="cardTitle">Upload Excel File</div>
                    <input
                        type="file"
                        accept=".xlsx,.xls"
                        onChange={(e) => {
                            const uploadedFile = e.target.files?.[0];
                            if (uploadedFile) handleFileUpload(uploadedFile);
                        }}
                    />
                    <div className="small" style={{ marginTop: 8 }}>
                        {file ? (
                            <>
                                <div>ชื่อไฟล์: {file.name}</div>
                                <div>ขนาด: {Math.round(file.size / 1024)} KB</div>
                                {data.length > 0 && <div>จำนวนแถว: {data.length.toLocaleString()}</div>}
                                {columns.length > 0 && <div>คอลัมน์: {columns.length} คอลัมน์</div>}
                            </>
                        ) : (
                            <div>ยังไม่ได้เลือกไฟล์</div>
                        )}
                    </div>
                </div>

                {data.length > 0 && (
                    <>
                        <div className="row">
                            <button className="btn" onClick={handleDownloadCSV}>
                                Download CSV
                            </button>
                            <button className="btn btnSecondary" onClick={reset}>
                                ล้างไฟล์
                            </button>
                            <div className="small">
                                ไฟล์ที่ได้: <b>รายงานผลการประเมิน_CreditScoring_รายย่อย_Agri_manual_YYYYMMDD.csv</b>
                            </div>
                        </div>

                        <div className="card" style={{ marginTop: 12 }}>
                            <div className="cardTitle">Preview (20 แถวแรก)</div>
                            <div className="tableWrap">
                                <table>
                                    <thead>
                                        <tr>
                                            {columns.map((col) => (
                                                <th key={col}>{col}</th>
                                            ))}
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {data.slice(0, 20).map((row, i) => (
                                            <tr key={i}>
                                                {columns.map((col) => (
                                                    <td key={col}>{String(row[col] ?? '')}</td>
                                                ))}
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                            {data.length > 20 && (
                                <div className="small" style={{ marginTop: 8 }}>
                                    แสดง 20 จาก {data.length.toLocaleString()} แถว
                                </div>
                            )}
                        </div>
                    </>
                )}

                {log && <pre className="pre">{log}</pre>}

                <div className="card" style={{ marginTop: 12 }}>
                    <div className="cardTitle">วิธีใช้งาน</div>
                    <div className="small">
                        <ol>
                            <li>Upload ไฟล์ Excel ที่ได้จาก CSV Merge Tool</li>
                            <li>ระบบจะอ่านข้อมูลจาก Sheet "Merged" และตัดคอลัมน์ VALIDATION ออกอัตโนมัติ</li>
                            <li>กด "Download CSV" เพื่อดาวน์โหลดไฟล์ที่สะอาดแล้ว</li>
                        </ol>
                    </div>
                </div>
            </main>
        </>
    );
}
