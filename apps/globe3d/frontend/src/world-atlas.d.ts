declare module 'world-atlas/land-110m.json' {
  const data: {
    type: string
    objects: Record<string, unknown>
    arcs: number[][][]
    transform?: { scale: number[]; translate: number[] }
  }
  export default data
}

declare module 'world-atlas/countries-110m.json' {
  const data: {
    type: string
    objects: Record<string, unknown>
    arcs: number[][][]
    transform?: { scale: number[]; translate: number[] }
  }
  export default data
}
