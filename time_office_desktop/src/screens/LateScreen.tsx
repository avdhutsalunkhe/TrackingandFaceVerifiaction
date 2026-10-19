import React from 'react';
import { Navigate } from 'react-router-dom';

export const LateScreen: React.FC = () => {
  return <Navigate to="/reports?type=late" replace />;
};
