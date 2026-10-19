import rawDepartmentList from './department_unit_id_name_list_updated.json';

export interface DepartmentUnitItem {
  department_id: number;
  unit_number: number;
  department_name: string;
}

export const DEPARTMENT_UNIT_LIST: DepartmentUnitItem[] = rawDepartmentList;

/**
 * Returns distinct unit numbers sorted in ascending order
 */
export const getUniqueUnitNumbers = (): number[] => {
  const units = new Set<number>();
  DEPARTMENT_UNIT_LIST.forEach((item) => units.add(item.unit_number));
  return Array.from(units).sort((a, b) => a - b);
};

/**
 * Filter departments based on search query (matches department_name or department_id or unit_number)
 */
export const searchDepartments = (query: string): DepartmentUnitItem[] => {
  const cleanQuery = query.trim().toLowerCase();
  if (!cleanQuery) return DEPARTMENT_UNIT_LIST;

  return DEPARTMENT_UNIT_LIST.filter((item) => {
    const nameMatch = item.department_name.toLowerCase().includes(cleanQuery);
    const idMatch = item.department_id.toString().includes(cleanQuery);
    const unitMatch = item.unit_number.toString().includes(cleanQuery);
    return nameMatch || idMatch || unitMatch;
  });
};

/**
 * Get department items matching a specific unit number
 */
export const getDepartmentsByUnit = (unitNumber: number): DepartmentUnitItem[] => {
  return DEPARTMENT_UNIT_LIST.filter((item) => item.unit_number === unitNumber);
};
