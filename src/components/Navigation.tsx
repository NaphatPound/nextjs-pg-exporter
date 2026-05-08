import Link from 'next/link';
import { useRouter } from 'next/router';

export default function Navigation() {
  const router = useRouter();

  return (
    <nav className="navigation">
      <div className="nav-container">
        <h2 className="nav-title">Interim Data Tools</h2>
        <div className="nav-links">
          <Link
            href="/"
            className={router.pathname === '/' ? 'nav-link active' : 'nav-link'}
          >
            🗄️ Data Exporter
          </Link>
          <Link
            href="/csv-merge"
            className={router.pathname === '/csv-merge' ? 'nav-link active' : 'nav-link'}
          >
            📊 CSV Merge Tool
          </Link>
          <Link
            href="/excel-to-csv"
            className={router.pathname === '/excel-to-csv' ? 'nav-link active' : 'nav-link'}
          >
            📄 Excel → CSV
          </Link>
        </div>
      </div>
    </nav>
  );
}
