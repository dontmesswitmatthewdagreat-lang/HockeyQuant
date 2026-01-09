import { createContext, useContext, useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';

const AuthContext = createContext({});

export const useAuth = () => useContext(AuthContext);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let subscription;
    let timeoutId;

    async function initAuth() {
      try {
        // Get initial session
        const { data: { session } } = await supabase.auth.getSession();
        setUser(session?.user ?? null);

        if (session?.user) {
          await fetchProfile(session.user.id);
        } else {
          setLoading(false);
        }
      } catch (err) {
        console.error('Auth init error:', err);
        setLoading(false);
      }
    }

    // Timeout fallback - if auth doesn't complete in 3 seconds, show login buttons anyway
    timeoutId = setTimeout(() => {
      setLoading(false);
    }, 3000);

    initAuth().finally(() => {
      clearTimeout(timeoutId);
    });

    // Listen for auth changes - with defensive check
    try {
      const authListener = supabase.auth.onAuthStateChange(async (event, session) => {
        setUser(session?.user ?? null);
        if (session?.user) {
          await fetchProfile(session.user.id);
        } else {
          setProfile(null);
          setLoading(false);
        }
      });
      subscription = authListener?.data?.subscription;
    } catch (err) {
      console.error('Auth listener error:', err);
      setLoading(false);
    }

    return () => {
      subscription?.unsubscribe();
      clearTimeout(timeoutId);
    };
  }, []);

  // Helper to get access token from localStorage
  function getAccessToken() {
    const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim();
    const storageKey = `sb-${new URL(supabaseUrl).hostname.split('.')[0]}-auth-token`;
    try {
      const stored = localStorage.getItem(storageKey);
      if (stored) {
        const parsed = JSON.parse(stored);
        return parsed?.access_token;
      }
    } catch (e) {
      console.error('Error getting token from localStorage:', e);
    }
    return null;
  }

  async function fetchProfile(userId) {
    let data = null;

    try {
      const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim();
      const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim();
      const accessToken = getAccessToken() || supabaseKey;

      const response = await fetch(
        `${supabaseUrl}/rest/v1/profiles?id=eq.${userId}&select=*`,
        {
          headers: {
            'apikey': supabaseKey,
            'Authorization': `Bearer ${accessToken}`,
          }
        }
      );

      if (response.ok) {
        const json = await response.json();
        if (json && json.length > 0) {
          data = json[0];
        }
      }
    } catch (e) {
      console.error('Error fetching profile:', e);
    }

    setProfile(data);
    setLoading(false);
  }

  async function signUp(email, password, username) {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { username }
      }
    });

    if (error) throw error;
    return data;
  }

  async function signIn(email, password) {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) throw error;
    return data;
  }

  async function signOut() {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
  }

  async function updateProfile(updates) {
    if (!user) {
      throw new Error('No user logged in');
    }

    const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim();
    const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim();
    const accessToken = getAccessToken() || supabaseKey;

    const response = await fetch(
      `${supabaseUrl}/rest/v1/profiles?id=eq.${user.id}`,
      {
        method: 'PATCH',
        headers: {
          'apikey': supabaseKey,
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          'Prefer': 'return=representation'
        },
        body: JSON.stringify(updates)
      }
    );

    if (!response.ok) {
      throw new Error(`Failed to update profile: ${response.status}`);
    }

    const json = await response.json();
    const data = json && json.length > 0 ? json[0] : null;
    setProfile(data);
    return data;
  }

  const value = {
    user,
    profile,
    loading,
    signUp,
    signIn,
    signOut,
    updateProfile,
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}
