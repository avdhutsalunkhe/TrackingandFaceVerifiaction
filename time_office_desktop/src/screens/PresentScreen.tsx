import React from 'react';
import { AttendanceScreen } from './AttendanceScreen';

export const PresentScreen: React.FC = () => {
  return (
    <AttendanceScreen
      fixedStatusFilter="PRESENT"
      pageTitle="Present Employees Monitoring"
      pageSubtitle="Employees who have successfully completed official attendance verification"
    />
  );
};
