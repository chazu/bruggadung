#ifndef lab_version_h__
#define lab_version_h__

/*
 *  You can maintain this file with `mulle-project-version`
 *  version:  major, minor, patch
 */
#define LAB_VERSION  ((0UL << 20) | (7 << 8) | 56)


static inline unsigned int   lab_get_version_major( void)
{
   return( LAB_VERSION >> 20);
}


static inline unsigned int   lab_get_version_minor( void)
{
   return( (LAB_VERSION >> 8) & 0xFFF);
}


static inline unsigned int   lab_get_version_patch( void)
{
   return( LAB_VERSION & 0xFF);
}

#endif
