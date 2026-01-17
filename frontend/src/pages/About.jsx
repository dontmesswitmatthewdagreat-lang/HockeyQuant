import './About.css';

function About() {
  return (
    <div className="about-page">
      {/* ============================================
          SECTION 1: ABOUT ME
          Edit the text below to describe yourself
          ============================================ */}
      <section className="about-section">
        <h2 className="section-title">About Me</h2>
        <p className="section-text">
          [YOUR TEXT HERE - Edit this paragraph to describe yourself. You can talk about
          your background, why you created HockeyQuant, your interest in hockey and
          data analytics, etc.]
        </p>
      </section>

      {/* ============================================
          SECTION 2: ABOUT THE MODELS
          Edit the text below to describe your prediction models
          ============================================ */}
      <section className="about-section">
        <h2 className="section-title">About the Models</h2>
        <p className="section-text">
          [YOUR TEXT HERE - Edit this paragraph to describe how the prediction models work.
          You can explain the data sources (MoneyPuck, ESPN, NHL API), the factors considered
          (fatigue, goalie stats, injuries, head-to-head history), and how confidence levels
          are calculated.]
        </p>
      </section>

      {/* ============================================
          OPTIONAL: ADD MORE SECTIONS
          Copy the section template below and paste it here to add more sections

          <section className="about-section">
            <h2 className="section-title">Your Section Title</h2>
            <p className="section-text">
              Your section text here.
            </p>
          </section>
          ============================================ */}
    </div>
  );
}

export default About;
