import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Home from './pages/Home';
import Predictions from './pages/Predictions';
import Teams from './pages/Teams';
import './App.css';

function App() {
  return (
    <Router>
      <div className="app">
        <Navbar />
        <main className="main-content">
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/predictions" element={<Predictions />} />
            <Route path="/teams" element={<Teams />} />
          </Routes>
        </main>
      </div>
    </Router>
  );
}

export default App;
