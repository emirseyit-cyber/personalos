import { MapValue, SkillResourceMap } from '../../types';

export const resourceMapToArray = (resources: SkillResourceMap): MapValue<SkillResourceMap>[] => {
  return Array.from(resources.entries()).map(([relativePath, data]) => ({
    relativePath,
    ...data,
  }));
};
